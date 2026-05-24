"""
    TableFieldSchema

A column in a BigQuery table schema.

Fields:
- `name::String`         — column name
- `type::String`         — BigQuery type (e.g. "STRING", "INT64", "FLOAT64", "BOOL", "TIMESTAMP")
- `mode::String`         — "NULLABLE" (default), "REQUIRED", or "REPEATED"
- `description::String?` — optional description
"""
struct TableFieldSchema
    name::String
    type::String
    mode::String
    description::Union{String, Nothing}
end

TableFieldSchema(name::AbstractString, type::AbstractString;
                 mode::AbstractString="NULLABLE",
                 description::Union{AbstractString, Nothing}=nothing) =
    TableFieldSchema(String(name), String(type), String(mode),
                     description === nothing ? nothing : String(description))

function _field_to_dict(f::TableFieldSchema)
    d = Dict{String, Any}("name" => f.name, "type" => f.type, "mode" => f.mode)
    if f.description !== nothing
        d["description"] = f.description
    end
    return d
end

"""
    Table

A BigQuery table reference and minimal metadata.
"""
struct Table
    project_id::String
    dataset_id::String
    table_id::String
    schema::Vector{TableFieldSchema}
    num_rows::Union{Int, Nothing}
end

function _parse_field(d)
    TableFieldSchema(
        String(d["name"]),
        String(d["type"]),
        haskey(d, "mode") ? String(d["mode"]) : "NULLABLE",
        haskey(d, "description") ? String(d["description"]) : nothing,
    )
end

function _parse_table(d)
    ref = haskey(d, "tableReference") ? d["tableReference"] : d
    fields = TableFieldSchema[]
    if haskey(d, "schema") && haskey(d["schema"], "fields")
        for f in d["schema"]["fields"]
            push!(fields, _parse_field(f))
        end
    end
    num_rows = nothing
    if haskey(d, "numRows")
        num_rows = parse(Int, String(d["numRows"]))
    end
    Table(
        String(get(ref, "projectId", "")),
        String(get(ref, "datasetId", "")),
        String(get(ref, "tableId",   "")),
        fields,
        num_rows,
    )
end

struct TableListPage <: GoogleApiCore.AbstractPage
    items::Vector{Table}
    next_page_token::Union{String, Nothing}
end

GoogleApiCore.get_items(p::TableListPage) = p.items
GoogleApiCore.get_next_token(p::TableListPage) = p.next_page_token

function _fetch_table_page(client::BQClient, dataset_id::AbstractString,
                            page_token::Union{Nothing, AbstractString})
    q = Dict{String, Any}()
    if page_token !== nothing && !isempty(page_token)
        q["pageToken"] = page_token
    end
    path = "bigquery/v2/projects/$(client.project_id)/datasets/$(dataset_id)/tables"
    resp = _bq_request(client, "GET", path; query=q)
    doc = JSON.parse(String(resp.body))
    raw = get(doc, "tables", nothing)
    items = raw === nothing ? Table[] : [_parse_table(t) for t in raw]
    token = haskey(doc, "nextPageToken") ? String(doc["nextPageToken"]) : nothing
    return TableListPage(items, token)
end

"""
    list_tables(client, dataset_id) -> PagedIterator{Table}

Iterate over all tables in a dataset.
"""
list_tables(client::BQClient, dataset_id::AbstractString) =
    GoogleApiCore.PagedIterator(token -> _fetch_table_page(client, dataset_id, token))

"""
    get_table(client, dataset_id, table_id) -> Table
"""
function get_table(client::BQClient, dataset_id::AbstractString,
                   table_id::AbstractString)
    path = "bigquery/v2/projects/$(client.project_id)/datasets/$(dataset_id)/tables/$(table_id)"
    resp = _bq_request(client, "GET", path)
    return _parse_table(JSON.parse(String(resp.body)))
end

"""
    create_table(client, dataset_id, table_id, schema::Vector{TableFieldSchema}) -> Table

Create a new empty table with the given schema.
"""
function create_table(client::BQClient, dataset_id::AbstractString,
                       table_id::AbstractString,
                       schema::Vector{TableFieldSchema})
    payload = Dict{String, Any}(
        "tableReference" => Dict(
            "projectId" => client.project_id,
            "datasetId" => String(dataset_id),
            "tableId"   => String(table_id),
        ),
        "schema" => Dict("fields" => [_field_to_dict(f) for f in schema]),
    )
    body = JSON.json(payload)
    path = "bigquery/v2/projects/$(client.project_id)/datasets/$(dataset_id)/tables"
    resp = _bq_request(client, "POST", path; body=body, content_type="application/json")
    return _parse_table(JSON.parse(String(resp.body)))
end

"""
    delete_table(client, dataset_id, table_id) -> Nothing
"""
function delete_table(client::BQClient, dataset_id::AbstractString,
                       table_id::AbstractString)
    path = "bigquery/v2/projects/$(client.project_id)/datasets/$(dataset_id)/tables/$(table_id)"
    _bq_request(client, "DELETE", path)
    return nothing
end
