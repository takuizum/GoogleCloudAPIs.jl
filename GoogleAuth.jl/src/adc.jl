# adc.jl

"""
Finds the default credentials file path created by `gcloud auth application-default login`.
"""
function get_well_known_file_path()
    if Sys.iswindows()
        appdata = get(ENV, "APPDATA", "")
        if !isempty(appdata)
            return joinpath(appdata, "gcloud", "application_default_credentials.json")
        end
    else
        return joinpath(homedir(), ".config", "gcloud", "application_default_credentials.json")
    end
    return ""
end

"""
Loads credentials from a JSON file.
"""
function load_credentials_from_file(path::String)
    if !isfile(path)
        error("Credentials file not found at: $path")
    end

    content = read(path, String)
    json_data = JSON3.read(content)

    if haskey(json_data, :type) && json_data.type == "service_account"
        # ServiceAccountCredentials uses StructTypes.Struct() with a default for
        # the `scopes` field, so JSON3 can deserialize key files directly.
        return JSON3.read(content, ServiceAccountCredentials)
    elseif haskey(json_data, :type) && json_data.type == "authorized_user"
        return JSON3.read(content, UserCredentials)
    elseif haskey(json_data, :type) && json_data.type == "external_account"
        error("External account (Workload Identity Federation) not yet implemented.")
    else
        error("Unknown credential type in file: $path")
    end
end

"""
    get_application_default() -> CachedCredentials

Implements the Application Default Credentials (ADC) strategy and wraps the
result in a `CachedCredentials` so the token is cached and auto-renewed.

Search order:
1. `GOOGLE_APPLICATION_CREDENTIALS` environment variable.
2. Well-known file (`~/.config/gcloud/application_default_credentials.json`).
3. Compute Engine / GKE / Cloud Run metadata server.
"""
function get_application_default()::CachedCredentials
    raw = _load_application_default()
    return CachedCredentials(raw)
end

function _load_application_default()::Credentials
    env_path = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", "")
    if !isempty(env_path)
        return load_credentials_from_file(env_path)
    end

    well_known_path = get_well_known_file_path()
    if !isempty(well_known_path) && isfile(well_known_path)
        return load_credentials_from_file(well_known_path)
    end

    if is_metadata_server_available()
        return ComputeCredentials()
    end

    error("Could not find Application Default Credentials. " *
          "Set GOOGLE_APPLICATION_CREDENTIALS, run `gcloud auth application-default login`, " *
          "or run on Google Cloud Platform.")
end
