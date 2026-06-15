"""
    Object

Metadata for an object stored in Google Cloud Storage.

Fields: `bucket`, `name`, `size` (bytes), `content_type`, `generation`.
"""
struct Object
    bucket::String
    name::String
    size::Int
    content_type::Union{String, Nothing}
    generation::Union{Int, Nothing}
end

function _parse_object(d)
    Object(
        String(d["bucket"]),
        String(d["name"]),
        haskey(d, "size") ? parse(Int, String(d["size"])) : 0,
        haskey(d, "contentType") ? String(d["contentType"]) : nothing,
        haskey(d, "generation") ? parse(Int, String(d["generation"])) : nothing,
    )
end

struct ObjectListPage <: GoogleApiCore.AbstractPage
    items::Vector{Object}
    next_page_token::Union{String, Nothing}
end

GoogleApiCore.get_items(p::ObjectListPage) = p.items
GoogleApiCore.get_next_token(p::ObjectListPage) = p.next_page_token

function _fetch_object_page(client::Client, bucket::AbstractString,
                            page_token::Union{Nothing, AbstractString};
                            prefix::Union{Nothing, AbstractString}=nothing)
    q = Dict{String, Any}()
    if page_token !== nothing && !isempty(page_token)
        q["pageToken"] = page_token
    end
    if prefix !== nothing
        q["prefix"] = prefix
    end
    resp = _request(client, "GET", "storage/v1/b/$(URIs.escapeuri(bucket))/o"; query=q)
    doc = JSON.parse(IOBuffer(resp.body))
    raw = get(doc, "items", nothing)
    items = raw === nothing ? Object[] : [_parse_object(o) for o in raw]
    token = haskey(doc, "nextPageToken") ? String(doc["nextPageToken"]) : nothing
    return ObjectListPage(items, token)
end

"""
    list_objects(client, bucket; prefix=nothing) -> PagedIterator{Object}
"""
list_objects(client::Client, bucket::AbstractString; prefix=nothing) =
    GoogleApiCore.PagedIterator(token -> _fetch_object_page(client, bucket, token; prefix=prefix))

"""
    get_object(client, bucket, name) -> Object

Fetch object metadata (does not download the object body).
"""
function get_object(client::Client, bucket::AbstractString, name::AbstractString)
    path = "storage/v1/b/$(URIs.escapeuri(bucket))/o/$(URIs.escapeuri(name))"
    resp = _request(client, "GET", path)
    return _parse_object(JSON.parse(IOBuffer(resp.body)))
end

"""
    download_object(client, bucket, name) -> Vector{UInt8}
    download_object(client, bucket, name, io) -> Nothing

Fetch the object body. The second form streams the body directly into the
provided `IO` (e.g. an open file) without buffering the whole object in memory,
so it is suitable for large objects:

```julia
open("local.bin", "w") do io
    download_object(gcs, "my-bucket", "big.bin", io)
end
```
"""
function download_object(client::Client, bucket::AbstractString, name::AbstractString)
    path = "storage/v1/b/$(URIs.escapeuri(bucket))/o/$(URIs.escapeuri(name))"
    resp = _request(client, "GET", path; query=Dict("alt" => "media"))
    return resp.body
end

function download_object(client::Client, bucket::AbstractString, name::AbstractString, io::IO)
    path = "storage/v1/b/$(URIs.escapeuri(bucket))/o/$(URIs.escapeuri(name))"
    _request(client, "GET", path; query=Dict("alt" => "media"), response_stream=io)
    return nothing
end

"""
    upload_object(client, bucket, name, data; content_type="application/octet-stream") -> Object

Simple (non-resumable) upload. `data` may be `Vector{UInt8}`, `AbstractString`,
or `IO`. An `IO` is streamed as the request body without being read into memory
first, so large files can be uploaded from an open handle:

```julia
open("big.bin") do io
    upload_object(gcs, "my-bucket", "big.bin", io)
end
```

Uses `uploadType=media` — for resumable/multipart uploads, see the roadmap.
"""
function upload_object(client::Client, bucket::AbstractString, name::AbstractString,
                       data::Union{AbstractVector{UInt8}, AbstractString, IO};
                       content_type::AbstractString="application/octet-stream")
    # IO is passed through so the transport layer streams it; bytes/strings are
    # normalized to a byte vector.
    body = data isa IO ? data : (data isa AbstractString ? Vector{UInt8}(data) : data)
    # GCS uses an upload-specific host on production but the same host on the
    # fake emulator. We always route relative to client.endpoint, which matches
    # both fake-gcs-server and the production "storage.googleapis.com" host
    # (the upload subdomain is reachable via the same canonical hostname).
    path = "upload/storage/v1/b/$(URIs.escapeuri(bucket))/o"
    q = Dict{String, Any}("uploadType" => "media", "name" => name)
    resp = _request(client, "POST", path; query=q, body=body, content_type=content_type)
    return _parse_object(JSON.parse(IOBuffer(resp.body)))
end

"""
    delete_object(client, bucket, name)

Delete an object from a bucket.
"""
function delete_object(client::Client, bucket::AbstractString, name::AbstractString)
    path = "storage/v1/b/$(URIs.escapeuri(bucket))/o/$(URIs.escapeuri(name))"
    _request(client, "DELETE", path)
    return nothing
end
