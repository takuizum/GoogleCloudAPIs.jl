# metadata.jl

const METADATA_HOST = "http://metadata.google.internal"
const METADATA_FLAVOR_HEADER = ["Metadata-Flavor" => "Google"]

"""
Checks if the Google Cloud metadata server is available.
"""
function is_metadata_server_available()
    try
        # Simple ping to the metadata server with a short timeout
        resp = HTTP.get(METADATA_HOST, headers=METADATA_FLAVOR_HEADER, readtimeout=2, connect_timeout=2, retry=false)
        return resp.status == 200 && haskey(Dict(resp.headers), "Metadata-Flavor")
    catch
        return false
    end
end

"""
Fetches an access token from the Google Cloud metadata server.
"""
function get_token(creds::ComputeCredentials)
    url = "$METADATA_HOST/computeMetadata/v1/instance/service-accounts/default/token"
    resp = HTTP.get(url, headers=METADATA_FLAVOR_HEADER)
    
    if resp.status == 200
        return JSON3.read(resp.body, Token)
    else
        error("Failed to fetch token from metadata server. Status: $(resp.status)")
    end
end

"""
Fetches the current project ID from the metadata server.
"""
function get_project_id()
    url = "$METADATA_HOST/computeMetadata/v1/project/project-id"
    resp = HTTP.get(url, headers=METADATA_FLAVOR_HEADER)
    
    if resp.status == 200
        return String(resp.body)
    else
        error("Failed to fetch project ID from metadata server.")
    end
end
