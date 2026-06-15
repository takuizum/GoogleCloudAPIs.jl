# client.jl
#
# Shared building blocks for service clients (GoogleCloudStorage, GoogleBigQuery,
# GoogleCloudPubSub). These are credential-agnostic on purpose: the auth header
# is injected via the `sign!` callback, so GoogleApiCore never depends on
# GoogleAuth.

"""
    resolve_endpoint(; emulator_host="", explicit=nothing, production) -> (endpoint::String, is_emulator::Bool)

Resolve a service endpoint and whether it points at a local emulator.

* If `explicit` is given it wins; it is treated as an emulator when it starts
  with `http://` (production endpoints use `https://`).
* Otherwise, if `emulator_host` (typically read from a `*_EMULATOR_HOST`
  environment variable) is non-empty, target it as an emulator, prefixing
  `http://` when it carries no scheme.
* Otherwise fall back to `production`.

```julia
ep, is_emu = resolve_endpoint(; emulator_host=get(ENV, "STORAGE_EMULATOR_HOST", ""),
                                explicit=nothing,
                                production="https://storage.googleapis.com")
```
"""
function resolve_endpoint(; emulator_host::AbstractString="",
                            explicit::Union{AbstractString, Nothing}=nothing,
                            production::AbstractString)
    if explicit !== nothing
        return String(explicit), startswith(explicit, "http://")
    end
    if !isempty(emulator_host)
        ep = startswith(emulator_host, "http") ? emulator_host : "http://$(emulator_host)"
        return String(ep), true
    end
    return String(production), false
end

"""
    service_request(method, endpoint, path; query, body, content_type, sign!, idempotent, kwargs...)

Build `"\$endpoint/\$path"` (URL-encoding `query` when present), attach a
`Content-Type` header when `content_type` is given, and delegate to
[`do_request_with_retry`](@ref). Extra `kwargs` are forwarded to the underlying
`HTTP.request` (e.g. `response_stream` for streaming downloads).
"""
function service_request(method::AbstractString, endpoint::AbstractString,
                         path::AbstractString;
                         query=nothing, body=nothing,
                         content_type::Union{AbstractString, Nothing}=nothing,
                         sign! = nothing, idempotent::Bool=false, kwargs...)
    url = "$(endpoint)/$(path)"
    if query !== nothing && !isempty(query)
        url *= "?" * URIs.escapeuri(query)
    end
    headers = Pair{String, String}[]
    content_type !== nothing && push!(headers, "Content-Type" => String(content_type))
    payload = body === nothing ? "" : body
    return do_request_with_retry(String(method), url, headers, payload;
                                 sign! = sign!, idempotent=idempotent, kwargs...)
end
