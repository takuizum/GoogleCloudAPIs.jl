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
    if endpoint === nothing
        emulator_host = get(ENV, "BIGQUERY_EMULATOR_HOST", "")
        if !isempty(emulator_host)
            ep = startswith(emulator_host, "http") ? emulator_host : "http://$(emulator_host)"
            return BQClient(project_id, nothing, ep, true, location)
        else
            resolved = creds === nothing ? GoogleAuth.get_application_default() : creds
            return BQClient(project_id, resolved, "https://bigquery.googleapis.com", false, location)
        end
    end
    is_emu = startswith(endpoint, "http://")
    resolved_creds = is_emu ? nothing : (creds === nothing ? GoogleAuth.get_application_default() : creds)
    return BQClient(project_id, resolved_creds, endpoint, is_emu, location)
end

function _request_headers(client::BQClient; content_type::Union{String, Nothing}=nothing)
    headers = Pair{String, String}[]
    if !client.is_emulator && client.creds !== nothing
        push!(headers, GoogleAuth.authorization_header(client.creds))
    end
    if content_type !== nothing
        push!(headers, "Content-Type" => content_type)
    end
    return headers
end

function _bq_request(client::BQClient, method::String, path::String;
                     query::Union{AbstractDict, Nothing}=nothing,
                     body=nothing,
                     content_type::Union{String, Nothing}=nothing)
    url = "$(client.endpoint)/$(path)"
    if query !== nothing && !isempty(query)
        url *= "?" * URIs.escapeuri(query)
    end
    headers = _request_headers(client; content_type=content_type)
    payload = body === nothing ? "" : body
    return GoogleApiCore.do_request_with_retry(method, url, headers, payload)
end
