"""
    BQClient(project_id; creds=nothing, endpoint=nothing)

A BigQuery REST API client.

If `BIGQUERY_EMULATOR_HOST` is set in the environment and `endpoint` is not
explicitly provided, the client targets the emulator with no authentication.
"""
struct BQClient
    project_id::String
    creds::Union{GoogleAuth.Credentials, Nothing}
    endpoint::String
    is_emulator::Bool
    location::String
end

function BQClient(project_id::String;
                  creds::Union{GoogleAuth.Credentials, Nothing}=nothing,
                  endpoint::Union{String, Nothing}=nothing,
                  location::String="US")
    ep, is_emu = GoogleApiCore.resolve_endpoint(;
        emulator_host = get(ENV, "BIGQUERY_EMULATOR_HOST", ""),
        explicit      = endpoint,
        production    = "https://bigquery.googleapis.com")
    resolved = is_emu ? nothing : (creds === nothing ? GoogleAuth.get_application_default() : creds)
    return BQClient(project_id, resolved, ep, is_emu, location)
end

function _bq_request(client::BQClient, method::String, path::String;
                     query::Union{AbstractDict, Nothing}=nothing,
                     body=nothing,
                     content_type::Union{String, Nothing}=nothing,
                     idempotent::Bool=false, kwargs...)
    return GoogleApiCore.service_request(method, client.endpoint, path;
        query=query, body=body, content_type=content_type,
        sign! = GoogleAuth.make_signer(client.creds; is_emulator=client.is_emulator),
        idempotent=idempotent, kwargs...)
end
