"""
    query(client, sql; format=:json, timeout_ms=10_000, max_results=nothing) -> Vector{NamedTuple} | Arrow.Table

Execute a SQL query against BigQuery and return the full result set.

* `format=:json` (default): parse rows from the REST API response into
  `Vector{NamedTuple}`. Works for all result sizes supported by `jobs.query`.
* `format=:arrow`: same as `:json` but converts the result to `Arrow.Table`
  client-side. Provides a columnar interface without requiring gRPC.

Note: true zero-copy Arrow streaming requires the BigQuery Storage Read API
(gRPC). That is not implemented in v0.1. See the project issue tracker for
the `GoogleBigQueryStorage.jl` roadmap item.

Pages are followed automatically via `jobs.getQueryResults`.
"""
function query(client::BQClient, sql::AbstractString;
               format::Symbol=:json,
               timeout_ms::Int=10_000,
               max_results::Union{Int, Nothing}=nothing)
    format in (:arrow, :json) || throw(ArgumentError("format must be :arrow or :json"))

    body = Dict{String, Any}(
        "query" => sql,
        "useLegacySql" => false,
        "timeoutMs" => timeout_ms,
        "location" => client.location,
    )
    if max_results !== nothing
        body["maxResults"] = max_results
    end
    encoded = JSON3.write(body)

    path = "bigquery/v2/projects/$(client.project_id)/queries"
    resp = _bq_request(client, "POST", path; body=encoded, content_type="application/json")
    initial = JSON3.read(resp.body)

    job_ref = initial["jobReference"]
    job_id = String(job_ref["jobId"])
    location = haskey(job_ref, "location") ? String(job_ref["location"]) : nothing

    rows = _collect_json(client, initial, job_id, location, max_results)
    format == :arrow ? _rows_to_arrow(rows) : rows
end

function _get_results_page(client::BQClient, job_id::AbstractString,
                           page_token::Union{AbstractString, Nothing},
                           location::Union{AbstractString, Nothing};
                           max_results::Union{Int, Nothing}=nothing)
    q = Dict{String, Any}()
    if page_token !== nothing && !isempty(page_token)
        q["pageToken"] = page_token
    end
    if location !== nothing
        q["location"] = location
    end
    if max_results !== nothing
        q["maxResults"] = max_results
    end
    path = "bigquery/v2/projects/$(client.project_id)/queries/$(job_id)"
    resp = _bq_request(client, "GET", path; query=q)
    return JSON3.read(resp.body)
end


function _collect_json(client::BQClient, first_page, job_id, location, max_results)
    schema_fields = _parse_schema(first_page)
    out = NamedTuple[]
    page = first_page
    while true
        if !get(page, "jobComplete", true)
            sleep(0.2)
            page = _get_results_page(client, job_id, nothing, location; max_results=max_results)
            continue
        end
        rows = get(page, "rows", nothing)
        if rows !== nothing
            for row in rows
                push!(out, _row_to_namedtuple(row, schema_fields))
            end
        end
        token = get(page, "pageToken", nothing)
        if token === nothing || isempty(token)
            break
        end
        page = _get_results_page(client, job_id, token, location; max_results=max_results)
    end
    return out
end

function _parse_schema(page)
    schema = get(page, "schema", nothing)
    schema === nothing && return Tuple{Symbol, String}[]
    fields = schema["fields"]
    return [(Symbol(f["name"]), String(f["type"])) for f in fields]
end
