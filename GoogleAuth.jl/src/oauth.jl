# oauth.jl
#
# Installed-App OAuth 2.0 flow with PKCE for desktop / CLI clients.
# Replicates the behavior of Python's `google_auth_oauthlib.flow.InstalledAppFlow`.

const _AUTH_ENDPOINT  = "https://accounts.google.com/o/oauth2/v2/auth"
const _TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
const _DEFAULT_SCOPE  = "https://www.googleapis.com/auth/cloud-platform"

# Characters allowed for PKCE code_verifier per RFC 7636 §4.1
const _PKCE_ALPHABET = collect(Char['A':'Z'; 'a':'z'; '0':'9'; '-'; '.'; '_'; '~'])

"""
    _base64url(bytes) -> String

URL-safe base64 without padding (RFC 4648 §5).
"""
function _base64url(bytes::AbstractVector{UInt8})
    s = Base64.base64encode(bytes)
    s = replace(s, '+' => '-', '/' => '_')
    return rstrip(s, '=')
end

"""
    _pkce_pair() -> (verifier::String, challenge::String)

Generate a PKCE `code_verifier` (43–128 chars from the unreserved set)
and its S256 `code_challenge`.
"""
function _pkce_pair(len::Int=64)
    43 <= len <= 128 || throw(ArgumentError("PKCE verifier length must be 43..128"))
    verifier = String(rand(Random.default_rng(), _PKCE_ALPHABET, len))
    challenge = _base64url(SHA.sha256(codeunits(verifier)))
    return verifier, challenge
end

"""
    _random_state(n=32) -> String

CSRF state token: URL-safe base64 of `n` random bytes.
"""
function _random_state(n::Int=32)
    bytes = rand(Random.default_rng(), UInt8, n)
    return _base64url(bytes)
end

"""
    _build_auth_url(; client_id, redirect_uri, scopes, state, code_challenge,
                      access_type="offline", prompt="consent") -> String
"""
function _build_auth_url(; client_id::AbstractString,
                          redirect_uri::AbstractString,
                          scopes::Vector{<:AbstractString},
                          state::AbstractString,
                          code_challenge::AbstractString,
                          access_type::AbstractString="offline",
                          prompt::AbstractString="consent")
    params = Dict{String,String}(
        "response_type"         => "code",
        "client_id"             => String(client_id),
        "redirect_uri"          => String(redirect_uri),
        "scope"                 => join(scopes, " "),
        "state"                 => String(state),
        "code_challenge"        => String(code_challenge),
        "code_challenge_method" => "S256",
        "access_type"           => String(access_type),
        "prompt"                => String(prompt),
    )
    return _AUTH_ENDPOINT * "?" * URIs.escapeuri(params)
end

# HTML returned to the browser after a successful (or failed) callback.
function _callback_html(message::AbstractString; success::Bool=true)
    color = success ? "#137333" : "#c5221f"
    title = success ? "Authentication complete" : "Authentication failed"
    """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>$title</title></head>
    <body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:3em">
      <h1 style="color:$color">$title</h1>
      <p>$message</p>
      <p>You can close this window and return to the application.</p>
    </body></html>
    """
end

"""
    _wait_for_callback(port, expected_state, timeout; bind_host="127.0.0.1") -> String

Run a one-shot HTTP server that captures the OAuth redirect, validates the
`state` parameter, and returns the authorization `code`. Throws on timeout,
state mismatch, or an OAuth error returned by Google.
"""
function _wait_for_callback(port::Int, expected_state::AbstractString, timeout::Real;
                            bind_host::AbstractString="127.0.0.1")
    result = Channel{Any}(1)
    host_ip = Sockets.getaddrinfo(bind_host)
    server = HTTP.serve!(host_ip, port) do req
        try
            uri = URIs.URI(req.target)
            q = URIs.queryparampairs(uri)
            params = Dict(String(k) => String(v) for (k, v) in q)
            if haskey(params, "error")
                msg = "OAuth error: $(params["error"])"
                put!(result, ErrorException(msg))
                return HTTP.Response(400, _callback_html(msg; success=false))
            end
            code  = get(params, "code",  "")
            state = get(params, "state", "")
            if isempty(code)
                put!(result, ErrorException("Callback missing `code` parameter"))
                return HTTP.Response(400, _callback_html("Missing authorization code"; success=false))
            end
            if state != expected_state
                put!(result, ErrorException("State mismatch — possible CSRF attempt"))
                return HTTP.Response(400, _callback_html("State mismatch"; success=false))
            end
            put!(result, code)
            return HTTP.Response(200, ["Content-Type" => "text/html"],
                                 _callback_html("You're authenticated."))
        catch e
            put!(result, e)
            return HTTP.Response(500, _callback_html("Internal error: $e"; success=false))
        end
    end

    try
        timer = Timer(timeout) do _t
            isready(result) || put!(result, ErrorException("Timeout waiting for OAuth callback ($(timeout)s)"))
        end
        outcome = take!(result)
        close(timer)
        outcome isa Exception && throw(outcome)
        return outcome::String
    finally
        close(server)
    end
end

"""
    _exchange_code(; client_id, client_secret, code, code_verifier, redirect_uri) -> Dict

Exchange an authorization `code` for `access_token` + `refresh_token`.
Returns the parsed JSON token response.
"""
function _exchange_code(; client_id::AbstractString,
                         client_secret::AbstractString,
                         code::AbstractString,
                         code_verifier::AbstractString,
                         redirect_uri::AbstractString,
                         token_endpoint::AbstractString=_TOKEN_ENDPOINT)
    body = URIs.escapeuri(Dict(
        "grant_type"    => "authorization_code",
        "code"          => String(code),
        "client_id"     => String(client_id),
        "client_secret" => String(client_secret),
        "redirect_uri"  => String(redirect_uri),
        "code_verifier" => String(code_verifier),
    ))
    resp = HTTP.post(token_endpoint,
                     ["Content-Type" => "application/x-www-form-urlencoded"],
                     body; status_exception=false)
    if resp.status != 200
        error("Token exchange failed (status $(resp.status)): $(String(resp.body))")
    end
    return JSON3.read(resp.body)
end

"""
    _free_port() -> Int

Ask the OS for an unused TCP port on localhost.
"""
function _free_port()
    srv = Sockets.listen(Sockets.localhost, 0)
    port = Sockets.getsockname(srv)[2]
    close(srv)
    return Int(port)
end

"""
    _save_user_credentials_to_well_known(creds::UserCredentials)

Persist refresh-token-based credentials to the gcloud ADC location so that
subsequent calls to `get_application_default()` pick them up automatically.
Creates the parent directory if necessary.
"""
function _save_user_credentials_to_well_known(creds::UserCredentials)
    path = get_well_known_file_path()
    isempty(path) && error("Could not determine well-known ADC path on this platform")
    mkpath(dirname(path))
    payload = Dict(
        "type"          => "authorized_user",
        "client_id"     => creds.client_id,
        "client_secret" => creds.client_secret,
        "refresh_token" => creds.refresh_token,
    )
    open(path, "w") do io
        JSON3.write(io, payload)
    end
    return path
end

"""
    authorize_via_browser(; client_id, client_secret, scopes, ...) -> CachedCredentials

Run the Installed-App OAuth 2.0 flow with PKCE:

1. Start a one-shot HTTP server on `bind_host:port` (random port by default).
2. Open the user's browser to Google's authorization endpoint
   (or print the URL when `open_browser=false`).
3. Wait for Google to redirect back with an authorization code.
4. Exchange the code for an access + refresh token at the token endpoint.
5. Wrap the result in `CachedCredentials` (auto-refreshing).

# Arguments
- `client_id::String`         — OAuth client ID (Desktop app type, from GCP Console)
- `client_secret::String`     — OAuth client secret
- `scopes::Vector{String}`    — Requested scopes (defaults to `cloud-platform`)
- `port::Int=0`               — Local callback port; `0` requests a free one
- `open_browser::Bool=true`   — Open the URL automatically when possible
- `save_adc::Bool=false`      — Persist the refresh token to the well-known ADC file.
  **Security warning:** When `true`, the refresh token (a long-lived credential that
  can be used to obtain new access tokens indefinitely) is written in plaintext to
  `~/.config/gcloud/application_default_credentials.json` (Linux/macOS) or
  `%APPDATA%\\gcloud\\application_default_credentials.json` (Windows).
  Any process or user that can read that file gains access to your Google Cloud
  resources. Leave this `false` (the default) to keep credentials in memory only,
  valid for the current Julia session.
- `timeout::Real=120`         — Seconds to wait for the callback
- `bind_host::String="127.0.0.1"` — Loopback interface to bind (do NOT use `0.0.0.0`)
- `token_endpoint::String`    — Override for testing
- `auth_endpoint::String`     — Override for testing

# Returns
A `CachedCredentials{UserCredentials}` ready for use with any service client.
"""
function authorize_via_browser(; client_id::AbstractString,
                                client_secret::AbstractString,
                                scopes::Vector{<:AbstractString}=[_DEFAULT_SCOPE],
                                port::Int=0,
                                open_browser::Bool=true,
                                save_adc::Bool=false,
                                timeout::Real=120,
                                bind_host::AbstractString="127.0.0.1",
                                token_endpoint::AbstractString=_TOKEN_ENDPOINT,
                                state::Union{AbstractString, Nothing}=nothing,
                                code_verifier::Union{AbstractString, Nothing}=nothing)
    actual_port = port == 0 ? _free_port() : port
    redirect_uri = "http://$(bind_host):$(actual_port)/"

    verifier, challenge = if code_verifier === nothing
        _pkce_pair()
    else
        v = String(code_verifier)
        (v, _base64url(SHA.sha256(codeunits(v))))
    end
    actual_state = state === nothing ? _random_state() : String(state)

    url = _build_auth_url(;
        client_id, redirect_uri, scopes,
        state=actual_state, code_challenge=challenge,
    )

    if open_browser
        opened = open_url(url)
        if !opened
            println("Could not open a browser. Please visit this URL to authorize:")
            println(url)
        end
    else
        println("Open the following URL in a browser to authorize:")
        println(url)
    end

    code = _wait_for_callback(actual_port, actual_state, timeout; bind_host=bind_host)

    resp = _exchange_code(;
        client_id, client_secret, code, code_verifier=verifier, redirect_uri,
        token_endpoint=token_endpoint,
    )

    refresh_token = String(get(resp, :refresh_token, ""))
    isempty(refresh_token) && error(
        "Token endpoint did not return a refresh_token. " *
        "Ensure access_type=offline and prompt=consent were honoured."
    )

    user_creds = UserCredentials(
        String(client_id),
        String(client_secret),
        refresh_token,
        "authorized_user",
    )

    if save_adc
        path = _save_user_credentials_to_well_known(user_creds)
        @warn """
        Credentials saved to disk (save_adc=true).
          Path : $path
          Risk : The refresh token is stored in plaintext. Anyone with read access
                 to that file can use your Google Cloud credentials indefinitely.
                 Run `rm "$path"` to revoke local access (does not revoke the token at Google).
        """
    end

    return CachedCredentials(user_creds)
end
