"""
    Dataset

A BigQuery dataset reference and minimal metadata.
"""
struct Dataset
    project_id::String
    dataset_id::String
    location::Union{String, Nothing}
    friendly_name::Union{String, Nothing}
end

function _parse_dataset(d)
    ref = haskey(d, "datasetReference") ? d["datasetReference"] : d
    Dataset(
        String(get(ref, "projectId", "")),
        String(get(ref, "datasetId", "")),
        haskey(d, "location") ? String(d["location"]) : nothing,
        haskey(d, "friendlyName") ? String(d["friendlyName"]) : nothing,
    )
end

struct DatasetListPage <: GoogleApiCore.AbstractPage
    items::Vector{Dataset}
    next_page_token::Union{String, Nothing}
end

GoogleApiCore.get_items(p::DatasetListPage) = p.items
GoogleApiCore.get_next_token(p::DatasetListPage) = p.next_page_token

function _fetch_dataset_page(client::BQClient, page_token::Union{Nothing, AbstractString})
    q = Dict{String, Any}()
    if page_token !== nothing && !isempty(page_token)
        q["pageToken"] = page_token
    end
    path = "bigquery/v2/projects/$(client.project_id)/datasets"
    resp = _bq_request(client, "GET", path; query=q)
    doc = JSON3.read(resp.body)
    raw = get(doc, "datasets", nothing)
    items = raw === nothing ? Dataset[] : [_parse_dataset(d) for d in raw]
    token = haskey(doc, "nextPageToken") ? String(doc["nextPageToken"]) : nothing
    return DatasetListPage(items, token)
end

"""
    list_datasets(client) -> PagedIterator{Dataset}

Iterate over all datasets in the client's project.
"""
list_datasets(client::BQClient) =
    GoogleApiCore.PagedIterator(token -> _fetch_dataset_page(client, token))

"""
    get_dataset(client, dataset_id) -> Dataset
"""
function get_dataset(client::BQClient, dataset_id::AbstractString)
    path = "bigquery/v2/projects/$(client.project_id)/datasets/$(dataset_id)"
    resp = _bq_request(client, "GET", path)
    return _parse_dataset(JSON3.read(resp.body))
end

"""
    create_dataset(client, dataset_id; location=client.location, friendly_name=nothing) -> Dataset
"""
function create_dataset(client::BQClient, dataset_id::AbstractString;
                        location::AbstractString=client.location,
                        friendly_name::Union{AbstractString, Nothing}=nothing)
    payload = Dict{String, Any}(
        "datasetReference" => Dict(
            "projectId" => client.project_id,
            "datasetId" => String(dataset_id),
        ),
        "location" => String(location),
    )
    if friendly_name !== nothing
        payload["friendlyName"] = String(friendly_name)
    end
    body = JSON3.write(payload)
    path = "bigquery/v2/projects/$(client.project_id)/datasets"
    resp = _bq_request(client, "POST", path; body=body, content_type="application/json")
    return _parse_dataset(JSON3.read(resp.body))
end

"""
    delete_dataset(client, dataset_id; delete_contents=false) -> Nothing

Delete a dataset. If `delete_contents=true`, also deletes all tables within it.
"""
function delete_dataset(client::BQClient, dataset_id::AbstractString;
                        delete_contents::Bool=false)
    q = Dict{String, Any}()
    if delete_contents
        q["deleteContents"] = "true"
    end
    path = "bigquery/v2/projects/$(client.project_id)/datasets/$(dataset_id)"
    _bq_request(client, "DELETE", path; query=q)
    return nothing
end
