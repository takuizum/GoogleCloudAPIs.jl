# credentials.jl

"""
Represents an OAuth 2.0 access token.
"""
struct Token
    access_token::String
    expires_in::Int
    token_type::String
    # Add other fields if necessary
end

StructTypes.StructType(::Type{Token}) = StructTypes.Struct()

"""
Abstract type for Google Cloud credentials.
"""
abstract type Credentials end

"""
Service Account Credentials (loaded from a JSON key file).
"""
struct ServiceAccountCredentials <: Credentials
    project_id::String
    client_email::String
    private_key_id::String
    private_key::String
    token_uri::String
    # Additional fields can be added
end

StructTypes.StructType(::Type{ServiceAccountCredentials}) = StructTypes.Struct()

"""
User Credentials (loaded from `gcloud auth application-default login`).
"""
struct UserCredentials <: Credentials
    client_id::String
    client_secret::String
    refresh_token::String
    type::String
end

StructTypes.StructType(::Type{UserCredentials}) = StructTypes.Struct()

"""
Compute Engine Metadata Credentials (used for Workload Identity / GCE).
"""
struct ComputeCredentials <: Credentials end

"""
Gets an access token using the given credentials.
"""
function get_token(creds::Credentials)
    error("get_token not implemented for $(typeof(creds))")
end

"""
Fetches an access token using UserCredentials (OAuth 2.0 refresh token).
"""
function get_token(creds::UserCredentials)
    url = "https://oauth2.googleapis.com/token"
    body = URIs.escapeuri(Dict(
        "client_id" => creds.client_id,
        "client_secret" => creds.client_secret,
        "refresh_token" => creds.refresh_token,
        "grant_type" => "refresh_token"
    ))
    headers = ["Content-Type" => "application/x-www-form-urlencoded"]
    
    resp = HTTP.post(url, headers, body)
    if resp.status == 200
        return JSON3.read(resp.body, Token)
    else
        error("Failed to fetch token. Status: $(resp.status), Body: $(String(resp.body))")
    end
end

"""
    CachedCredentials(inner)

Wraps any `Credentials` subtype and caches the access token until it is
within 5 minutes of expiry, then fetches a fresh one automatically.
Thread-safe: concurrent callers share a single `ReentrantLock`.

`get_application_default()` returns a `CachedCredentials`-wrapped value
by default. You can also wrap manually:

```julia
creds = CachedCredentials(ServiceAccountCredentials(...))
```
"""
mutable struct CachedCredentials{C <: Credentials} <: Credentials
    inner::C
    _token::Union{Token, Nothing}
    _obtained_at::Float64  # Unix timestamp of last successful fetch
    _lock::ReentrantLock
end

CachedCredentials(inner::C) where {C <: Credentials} =
    CachedCredentials{C}(inner, nothing, 0.0, ReentrantLock())

function get_token(c::CachedCredentials)
    Base.@lock c._lock begin
        if c._token === nothing ||
           time() > c._obtained_at + c._token.expires_in - 300  # 5-min buffer
            c._token = get_token(c.inner)
            c._obtained_at = time()
        end
        return c._token
    end
end

"""
Returns an `Authorization` HTTP header pair (`"Authorization" => "Bearer <token>"`)
for the given credentials. Fetches a fresh access token on every call.
"""
function authorization_header(creds::Credentials)
    token = get_token(creds)
    return "Authorization" => "Bearer $(token.access_token)"
end

"""
Fetches an access token using ServiceAccountCredentials.
Requires generating a JWT signed with the private key.
"""
function get_token(creds::ServiceAccountCredentials; scopes::Vector{String}=["https://www.googleapis.com/auth/cloud-platform"])
    iat = Dates.datetime2unix(Dates.now(UTC)) |> Int
    exp = iat + 3600

    claim = Dict(
        "iss" => creds.client_email,
        "scope" => join(scopes, " "),
        "aud" => creds.token_uri,
        "exp" => exp,
        "iat" => iat
    )
    
    # Needs a parsed RSA key
    # Workaround for RS256 using JSONWebTokens.jl
    jwt = JSONWebTokens.encode(JSONWebTokens.RS256(creds.private_key), claim)

    body = URIs.escapeuri(Dict(
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => jwt
    ))
    headers = ["Content-Type" => "application/x-www-form-urlencoded"]

    resp = HTTP.post(creds.token_uri, headers, body)
    if resp.status == 200
        return JSON3.read(resp.body, Token)
    else
        error("Failed to fetch token for Service Account. Status: $(resp.status)")
    end
end
