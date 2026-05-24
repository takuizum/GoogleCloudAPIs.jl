"""
    Client(project_id; creds=nothing, endpoint=nothing)

A Google Cloud Storage JSON API client.

If `STORAGE_EMULATOR_HOST` is set in the environment and `endpoint` is not
provided, the client targets the emulator with no authentication.
"""
struct Client
    project_id::String
    creds::Union{GoogleAuth.Credentials, Nothing}
    endpoint::String
    is_emulator::Bool
end

function Client(project_id::String;
                creds::Union{GoogleAuth.Credentials, Nothing}=nothing,
                endpoint::Union{String, Nothing}=nothing)
    if endpoint === nothing
        emulator_host = get(ENV, "STORAGE_EMULATOR_HOST", "")
        if !isempty(emulator_host)
            ep = startswith(emulator_host, "http") ? emulator_host : "http://$(emulator_host)"
            return Client(project_id, nothing, ep, true)
        end
        resolved = creds === nothing ? GoogleAuth.get_application_default() : creds
        return Client(project_id, resolved, "https://storage.googleapis.com", false)
    end
    is_emu = startswith(endpoint, "http://")
    resolved = is_emu ? nothing : (creds === nothing ? GoogleAuth.get_application_default() : creds)
    return Client(project_id, resolved, endpoint, is_emu)
end

function _headers(; content_type::Union{String, Nothing}=nothing)
    h = Pair{String, String}[]
    if content_type !== nothing
        push!(h, "Content-Type" => content_type)
    end
    return h
end

function _make_signer(client::Client)
    if client.is_emulator || client.creds === nothing
        return nothing
    end
    creds = client.creds
    return req -> push!(req.headers, GoogleAuth.authorization_header(creds))
end

function _url(client::Client, path::AbstractString; query=nothing)
    url = "$(client.endpoint)/$(path)"
    if query !== nothing && !isempty(query)
        url *= "?" * URIs.escapeuri(query)
    end
    return url
end

function _request(client::Client, method::String, path::AbstractString;
                  query=nothing, body=nothing, content_type=nothing)
    url = _url(client, path; query=query)
    headers = _headers(; content_type=content_type)
    payload = body === nothing ? "" : body
    return GoogleApiCore.do_request_with_retry(method, url, headers, payload;
                                               sign! = _make_signer(client))
end
