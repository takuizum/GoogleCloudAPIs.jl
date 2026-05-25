using GoogleAuth
using JSON3

function first_env(names...)
    for name in names
        value = get(ENV, name, "")
        isempty(value) || return value
    end
    return ""
end

function load_client_credentials()
    json_path = first_env("GOOGLE_AUTH_CLIENT_SECRET_FILE",
                          "GOOGLE_CLIENT_SECRET_FILE",
                          "GOOGLE_APPLICATION_CREDENTIALS")
    if !isempty(json_path)
        data = JSON3.read(read(json_path, String))
        if haskey(data, "installed")
            return String(data["installed"]["client_id"]), String(data["installed"]["client_secret"])
        elseif haskey(data, "web")
            return String(data["web"]["client_id"]), String(data["web"]["client_secret"])
        else
            error("Client secret JSON must contain an `installed` or `web` object")
        end
    end

    client_id = first_env("GOOGLE_AUTH_CLIENT_ID", "GOOGLE_CLIENT_ID")
    client_secret = first_env("GOOGLE_AUTH_CLIENT_SECRET", "GOOGLE_CLIENT_SECRET")
    isempty(client_id) && error("Set GOOGLE_AUTH_CLIENT_ID or GOOGLE_CLIENT_ID, or point GOOGLE_AUTH_CLIENT_SECRET_FILE to a client secret JSON")
    isempty(client_secret) && error("Set GOOGLE_AUTH_CLIENT_SECRET or GOOGLE_CLIENT_SECRET, or point GOOGLE_AUTH_CLIENT_SECRET_FILE to a client secret JSON")
    return client_id, client_secret
end

client_id, client_secret = load_client_credentials()
open_browser = lowercase(get(ENV, "GOOGLE_AUTH_OPEN_BROWSER", "true")) != "false"
save_adc = lowercase(get(ENV, "GOOGLE_AUTH_SAVE_ADC", "false")) == "true"
timeout = parse(Int, get(ENV, "GOOGLE_AUTH_TIMEOUT", "300"))

println("Starting browser authentication...")
println("Complete the login in the browser window that opens.")

creds = authorize_via_browser(;
    client_id=client_id,
    client_secret=client_secret,
    scopes=["https://www.googleapis.com/auth/cloud-platform"],
    open_browser=open_browser,
    save_adc=save_adc,
    timeout=timeout,
)

println("Authentication completed.")
println(creds)
println(authorization_header(creds))
