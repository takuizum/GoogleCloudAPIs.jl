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
    ep, is_emu = GoogleApiCore.resolve_endpoint(;
        emulator_host = get(ENV, "STORAGE_EMULATOR_HOST", ""),
        explicit      = endpoint,
        production    = "https://storage.googleapis.com")
    resolved = is_emu ? nothing : (creds === nothing ? GoogleAuth.get_application_default() : creds)
    return Client(project_id, resolved, ep, is_emu)
end

function _request(client::Client, method::String, path::AbstractString;
                  query=nothing, body=nothing, content_type=nothing,
                  idempotent::Bool=false, kwargs...)
    return GoogleApiCore.service_request(method, client.endpoint, path;
        query=query, body=body, content_type=content_type,
        sign! = GoogleAuth.make_signer(client.creds; is_emulator=client.is_emulator),
        idempotent=idempotent, kwargs...)
end
