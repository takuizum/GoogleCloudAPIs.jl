struct Bucket
    name::String
    location::Union{String, Nothing}
    storage_class::Union{String, Nothing}
end

function _parse_bucket(d)
    Bucket(
        String(d["name"]),
        haskey(d, "location") ? String(d["location"]) : nothing,
        haskey(d, "storageClass") ? String(d["storageClass"]) : nothing,
    )
end

struct BucketListPage <: GoogleApiCore.AbstractPage
    items::Vector{Bucket}
    next_page_token::Union{String, Nothing}
end

GoogleApiCore.get_items(p::BucketListPage) = p.items
GoogleApiCore.get_next_token(p::BucketListPage) = p.next_page_token

function _fetch_bucket_page(client::Client, page_token::Union{Nothing, AbstractString})
    q = Dict{String, Any}("project" => client.project_id)
    if page_token !== nothing && !isempty(page_token)
        q["pageToken"] = page_token
    end
    resp = _request(client, "GET", "storage/v1/b"; query=q)
    doc = JSON3.read(resp.body)
    raw_items = get(doc, "items", nothing)
    items = raw_items === nothing ? Bucket[] : [_parse_bucket(b) for b in raw_items]
    next_token = haskey(doc, "nextPageToken") ? String(doc["nextPageToken"]) : nothing
    return BucketListPage(items, next_token)
end

"""
    list_buckets(client) -> PagedIterator{Bucket}

Iterate over all buckets belonging to the client's project.
"""
list_buckets(client::Client) =
    GoogleApiCore.PagedIterator(token -> _fetch_bucket_page(client, token))

"""
    get_bucket(client, name) -> Bucket
"""
function get_bucket(client::Client, name::AbstractString)
    resp = _request(client, "GET", "storage/v1/b/$(URIs.escapeuri(name))")
    return _parse_bucket(JSON3.read(resp.body))
end

"""
    create_bucket(client, name; location="US", storage_class="STANDARD") -> Bucket

Create a new GCS bucket in the client's project.
"""
function create_bucket(client::Client, name::AbstractString;
                       location::AbstractString="US",
                       storage_class::AbstractString="STANDARD")
    body = JSON3.write(Dict(
        "name"         => String(name),
        "location"     => String(location),
        "storageClass" => String(storage_class),
    ))
    resp = _request(client, "POST", "storage/v1/b";
                    query=Dict("project" => client.project_id),
                    body=body, content_type="application/json")
    return _parse_bucket(JSON3.read(resp.body))
end

"""
    delete_bucket(client, name)

Delete a GCS bucket. The bucket must be empty.
"""
function delete_bucket(client::Client, name::AbstractString)
    _request(client, "DELETE", "storage/v1/b/$(URIs.escapeuri(name))")
    return nothing
end
