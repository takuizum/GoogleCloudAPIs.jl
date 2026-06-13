"""
    query(client, sql; params=nothing, format=:json, timeout_ms=10_000,
          max_results=nothing, poll_timeout=600.0) -> Vector{NamedTuple} | Arrow.Table

Execute a SQL query against BigQuery and return the full result set.

* `params`: query parameters — pass a `Dict` for named parameters
  (referenced as `@name` in SQL) or a `Vector` for positional ones
  (referenced as `?`). Prefer parameters over string interpolation to
  avoid SQL injection. `DateTime` parameters are sent as `TIMESTAMP` and
  **interpreted as UTC**; pass DATETIME values as `String`s instead.
  See [`_bq_param_type`](@ref) for the type mapping.
* `format=:json` (default): parse rows from the REST API response into
  `Vector{NamedTuple}`. Works for all result sizes supported by `jobs.query`.
* `format=:arrow`: same as `:json` but converts the result to `Arrow.Table`
  client-side. Provides a columnar interface without requiring gRPC.
* `timeout_ms`: server-side wait passed to `jobs.query` (`timeoutMs`).
* `poll_timeout`: client-side deadline in seconds for the whole job to
  complete. Throws `GoogleApiCore.TimeoutError` when exceeded.

```julia
query(bq, "SELECT name FROM t WHERE age > @min_age AND city = @city";
      params=Dict("min_age" => 20, "city" => "Tokyo"))
query(bq, "SELECT ? + ?"; params=[1, 2])
```

Column values are converted to Julia types — `INT64 → Int64`,
`FLOAT64 → Float64`, `BOOL → Bool`, `TIMESTAMP/DATETIME → Dates.DateTime`
(TIMESTAMP is UTC; both truncate to millisecond precision),
`DATE → Dates.Date`, `TIME → Dates.Time`, `BYTES → Vector{UInt8}`,
`RECORD/STRUCT →` nested `NamedTuple`, `REPEATED →` `Vector`. `NUMERIC` and
`BIGNUMERIC` are kept as lossless `String`s (parse explicitly if you can
tolerate `Float64` rounding); SQL `NULL` becomes `missing`. See
[`_coerce_value`](@ref) for the full table.

Note: true zero-copy Arrow streaming requires the BigQuery Storage Read API
(gRPC). That is not implemented in v0.1. See the project issue tracker for
the `GoogleBigQueryStorage.jl` roadmap item.

Pages are followed automatically via `jobs.getQueryResults`.
"""
function query(client::BQClient, sql::AbstractString;
               params::Union{AbstractDict, AbstractVector, Nothing}=nothing,
               format::Symbol=:json,
               timeout_ms::Int=10_000,
               max_results::Union{Int, Nothing}=nothing,
               poll_timeout::Real=600.0)
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
    if params !== nothing
        mode, qp = _build_query_parameters(params)
        body["parameterMode"]   = mode
        body["queryParameters"] = qp
    end
    encoded = JSON.json(body)

    path = "bigquery/v2/projects/$(client.project_id)/queries"
    resp = _bq_request(client, "POST", path; body=encoded, content_type="application/json")
    initial = JSON.parse(IOBuffer(resp.body))

    job_ref = initial["jobReference"]
    job_id = String(job_ref["jobId"])
    location = haskey(job_ref, "location") ? String(job_ref["location"]) : nothing

    deadline = time() + Float64(poll_timeout)
    rows = _collect_json(client, initial, job_id, location, max_results, deadline,
                         Float64(poll_timeout))
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
    return JSON.parse(IOBuffer(resp.body))
end


function _collect_json(client::BQClient, first_page, job_id, location, max_results,
                       deadline::Float64, poll_timeout::Float64)
    out = NamedTuple[]
    page = first_page
    poll_interval = 0.2
    # The schema is only present once the job is complete, so it must be
    # parsed from the first *complete* page (the initial jobs.query response
    # carries no schema when jobComplete=false).
    schema_fields = nothing
    while true
        if !get(page, "jobComplete", true)
            if time() >= deadline
                throw(GoogleApiCore.TimeoutError(
                    "BigQuery job $(job_id) did not complete", poll_timeout))
            end
            sleep(poll_interval)
            poll_interval = min(poll_interval * 1.5, 5.0)
            page = _get_results_page(client, job_id, nothing, location; max_results=max_results)
            continue
        end
        if schema_fields === nothing
            schema_fields = _parse_schema(page)
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
    schema === nothing && return BQField[]
    return _parse_schema_fields(schema["fields"])
end

function _parse_schema_fields(fields)
    return [BQField(Symbol(f["name"]),
                    uppercase(String(f["type"])),
                    String(get(f, "mode", "NULLABLE")),
                    haskey(f, "fields") ? _parse_schema_fields(f["fields"]) : BQField[])
            for f in fields]
end
