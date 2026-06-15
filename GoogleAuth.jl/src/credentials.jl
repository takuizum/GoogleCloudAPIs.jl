# credentials.jl

"""
    _parse_google_error_body(body, status) -> String

Extract a human-readable message from a Google API error response body without
leaking the raw payload. Handles both the REST API error envelope
`{"error":{"code":…,"message":…,"status":…}}` and the OAuth token endpoint
format `{"error":"…","error_description":"…"}`.
"""
function _parse_google_error_body(body::Union{String, AbstractVector{UInt8}}, status::Integer)
    body_str = body isa String ? body : String(copy(body))
    try
        j = JSON.parse(body_str)
        if haskey(j, "error")
            e = j["error"]
            if e isa AbstractDict
                code = get(e, "code", status)
                msg  = get(e, "message", "unknown error")
                st   = string(get(e, "status", ""))
                return isempty(st) ? "status=$code: $msg" : "status=$code ($st): $msg"
            elseif e isa AbstractString
                desc = string(get(j, "error_description", ""))
                return isempty(desc) ? "status=$status: $e" : "status=$status: $e — $desc"
            end
        end
    catch
    end
    return "status=$status: $(first(body_str, 200))"
end

"""
Represents an OAuth 2.0 access token.
"""
struct Token
    access_token::String
    expires_in::Int
    token_type::String
end

Token(d::AbstractDict) = Token(String(d["access_token"]), Int(d["expires_in"]), String(d["token_type"]))

function Base.show(io::IO, t::Token)
    print(io, "Token(token_type=$(repr(t.token_type)), expires_in=$(t.expires_in), access_token=<redacted>)")
end

"""
Abstract type for Google Cloud credentials.
"""
abstract type Credentials end

"""
Service Account Credentials (loaded from a JSON key file).

Use `with_scopes(creds, scopes)` to attach OAuth scopes before wrapping in
`CachedCredentials`; scopes baked into the struct are used by `get_token`.
"""
struct ServiceAccountCredentials <: Credentials
    project_id::String
    client_email::String
    private_key_id::String
    private_key::String
    token_uri::String
    scopes::Vector{String}

    ServiceAccountCredentials(project_id, client_email, private_key_id, private_key, token_uri) =
        new(String(project_id), String(client_email), String(private_key_id),
            String(private_key), String(token_uri), String[])

    ServiceAccountCredentials(project_id, client_email, private_key_id, private_key, token_uri, scopes) =
        new(String(project_id), String(client_email), String(private_key_id),
            String(private_key), String(token_uri), collect(String, scopes))
end

function ServiceAccountCredentials(d::AbstractDict)
    scopes = get(d, "scopes", String[])
    return ServiceAccountCredentials(
        String(d["project_id"]),
        String(d["client_email"]),
        String(d["private_key_id"]),
        String(d["private_key"]),
        String(d["token_uri"]),
        scopes isa AbstractVector ? collect(String, scopes) : String[]
    )
end

function Base.show(io::IO, c::ServiceAccountCredentials)
    scopes_str = isempty(c.scopes) ? "(default)" : join(c.scopes, ", ")
    print(io, "ServiceAccountCredentials(client_email=$(repr(c.client_email)), " *
              "project_id=$(repr(c.project_id)), scopes=$(repr(scopes_str)), " *
              "private_key=<redacted>)")
end

"""
    with_scopes(creds::ServiceAccountCredentials, scopes) -> ServiceAccountCredentials

Return a new `ServiceAccountCredentials` with the given OAuth scopes baked in.
The original credentials are not modified. The returned value should be wrapped
in `CachedCredentials` so the scoped token is cached correctly.

```julia
creds = with_scopes(sa, ["https://www.googleapis.com/auth/bigquery"])
cached = CachedCredentials(creds)
```
"""
with_scopes(c::ServiceAccountCredentials, scopes::AbstractVector{<:AbstractString}) =
    ServiceAccountCredentials(c.project_id, c.client_email, c.private_key_id,
                              c.private_key, c.token_uri, scopes)

"""
User Credentials (loaded from `gcloud auth application-default login`).
"""
struct UserCredentials <: Credentials
    client_id::String
    client_secret::String
    refresh_token::String
    type::String
end

function UserCredentials(d::AbstractDict)
    return UserCredentials(
        String(d["client_id"]),
        String(d["client_secret"]),
        String(d["refresh_token"]),
        String(get(d, "type", "authorized_user"))
    )
end

function Base.show(io::IO, ::UserCredentials)
    print(io, "UserCredentials(client_secret=<redacted>, refresh_token=<redacted>)")
end

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
        "client_id"     => creds.client_id,
        "client_secret" => creds.client_secret,
        "refresh_token" => creds.refresh_token,
        "grant_type"    => "refresh_token"
    ))
    headers = ["Content-Type" => "application/x-www-form-urlencoded"]

    resp = HTTP.post(url, headers, body; status_exception=false)
    if resp.status == 200
        return Token(JSON.parse(IOBuffer(resp.body)))
    else
        error("Failed to refresh user token: " *
              _parse_google_error_body(resp.body, resp.status))
    end
end

"""
Fetches an access token using ServiceAccountCredentials via a signed JWT.

Scopes are taken from the credentials object (set via `with_scopes`).
If no scopes are set, defaults to `https://www.googleapis.com/auth/cloud-platform`.
"""
function get_token(creds::ServiceAccountCredentials)
    effective_scopes = isempty(creds.scopes) ?
        ["https://www.googleapis.com/auth/cloud-platform"] : creds.scopes

    iat = Dates.datetime2unix(Dates.now(UTC)) |> Int
    exp = iat + 3600

    claim = Dict(
        "iss"   => creds.client_email,
        "scope" => join(effective_scopes, " "),
        "aud"   => creds.token_uri,
        "exp"   => exp,
        "iat"   => iat
    )

    jwt = JSONWebTokens.encode(JSONWebTokens.RS256(creds.private_key), claim)

    body = URIs.escapeuri(Dict(
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion"  => jwt
    ))
    headers = ["Content-Type" => "application/x-www-form-urlencoded"]

    resp = HTTP.post(creds.token_uri, headers, body; status_exception=false)
    if resp.status == 200
        return Token(JSON.parse(IOBuffer(resp.body)))
    else
        error("Failed to fetch token for service account ($(creds.client_email)): " *
              _parse_google_error_body(resp.body, resp.status))
    end
end

const _IAM_CREDENTIALS_BASE =
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts"

"""
    ImpersonatedCredentials(source, target_principal, scopes; lifetime=3600)

Credentials that impersonate a target service account by calling the
[IAM Credentials API](https://cloud.google.com/iam/docs/reference/credentials/rest).

The `source` credentials must have the **Service Account Token Creator**
(`roles/iam.serviceAccountTokenCreator`) role on the target principal.

# Arguments
- `source::Credentials`       — Credentials authorizing the impersonation (e.g.
  `CachedCredentials{ServiceAccountCredentials}` or the result of
  `get_application_default()`).
- `target_principal::String`  — Email of the service account to impersonate
  (e.g. `"sa@project.iam.gserviceaccount.com"`).
- `scopes`                    — OAuth scopes to request (any `AbstractVector{<:AbstractString}`).
- `lifetime::Int=3600`        — Token lifetime in seconds (maximum 3600).

Use `with_scopes(c, scopes)` to change the scopes on an existing
`ImpersonatedCredentials` without altering the source or target.

```julia
source = get_application_default()
creds  = CachedCredentials(
    ImpersonatedCredentials(source, "worker@proj.iam.gserviceaccount.com",
                            ["https://www.googleapis.com/auth/bigquery"])
)
```
"""
struct ImpersonatedCredentials <: Credentials
    source::Credentials
    target_principal::String
    scopes::Vector{String}
    lifetime::Int
    _iam_base_url::String  # Overrideable for testing; production default is _IAM_CREDENTIALS_BASE

    function ImpersonatedCredentials(source::Credentials,
                                     target_principal::AbstractString,
                                     scopes::AbstractVector{<:AbstractString};
                                     lifetime::Int=3600,
                                     _iam_base_url::AbstractString=_IAM_CREDENTIALS_BASE)
        1 <= lifetime <= 3600 ||
            throw(ArgumentError("lifetime must be between 1 and 3600 seconds"))
        new(source, String(target_principal), collect(String, scopes),
            lifetime, String(_iam_base_url))
    end
end

function Base.show(io::IO, c::ImpersonatedCredentials)
    print(io, "ImpersonatedCredentials(target=$(repr(c.target_principal)), " *
              "scopes=$(repr(join(c.scopes, ", "))))")
end

with_scopes(c::ImpersonatedCredentials, scopes::AbstractVector{<:AbstractString}) =
    ImpersonatedCredentials(c.source, c.target_principal, scopes;
                            lifetime=c.lifetime, _iam_base_url=c._iam_base_url)

"""
    _generate_access_token(url, bearer, scopes, lifetime) -> Token

Call an IAM Credentials `generateAccessToken` endpoint with a bearer token and
convert the RFC3339 `expireTime` in the response into a seconds-remaining
`Token`. Shared by `ImpersonatedCredentials` and `ExternalAccountCredentials`.
"""
function _generate_access_token(url::String, bearer::String,
                                scopes::Vector{String}, lifetime::Int;
                                error_prefix::String="Failed to generate impersonated access token")
    headers = [
        "Authorization"  => "Bearer $(bearer)",
        "Content-Type"   => "application/json",
    ]
    body = JSON.json(Dict(
        "scope"    => scopes,
        "lifetime" => "$(lifetime)s",
    ))

    resp = HTTP.post(url, headers, body; status_exception=false)
    if resp.status != 200
        error(error_prefix * ": " * _parse_google_error_body(resp.body, resp.status))
    end

    j = JSON.parse(IOBuffer(resp.body))

    # expireTime is an RFC3339 timestamp; convert to seconds-remaining for Token.
    expire_str = replace(String(j["expireTime"]), r"(\.\d+)?Z$" => "")
    expire_dt  = Dates.DateTime(expire_str, Dates.dateformat"yyyy-mm-ddTHH:MM:SS")
    expires_in = max(0, round(Int, Dates.datetime2unix(expire_dt) - time()))

    return Token(String(j["accessToken"]), expires_in, "Bearer")
end

function get_token(creds::ImpersonatedCredentials)
    src_token = get_token(creds.source)
    url = "$(creds._iam_base_url)/$(creds.target_principal):generateAccessToken"
    return _generate_access_token(url, src_token.access_token,
                                  creds.scopes, creds.lifetime;
                                  error_prefix="Failed to impersonate $(creds.target_principal)")
end

"""
    CachedCredentials(inner)

Wraps any `Credentials` subtype and caches the access token until it is
within 5 minutes of expiry, then fetches a fresh one automatically.
Thread-safe: concurrent callers share a single `ReentrantLock`.

`get_application_default()` returns a `CachedCredentials`-wrapped value
by default. You can also wrap manually:

```julia
creds = CachedCredentials(with_scopes(sa, ["https://www.googleapis.com/auth/bigquery"]))
```
"""
mutable struct CachedCredentials{C <: Credentials} <: Credentials
    inner::C
    _token::Union{Token, Nothing}
    _obtained_at::Float64
    _lock::ReentrantLock
end

CachedCredentials(inner::C) where {C <: Credentials} =
    CachedCredentials{C}(inner, nothing, 0.0, ReentrantLock())

function Base.show(io::IO, c::CachedCredentials)
    print(io, "CachedCredentials(inner=$(c.inner), cached=$(c._token !== nothing ? "yes" : "no"))")
end

function get_token(c::CachedCredentials)
    Base.@lock c._lock begin
        if c._token === nothing ||
           time() > c._obtained_at + c._token.expires_in - 300
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
    make_signer(creds; is_emulator=false) -> Union{Function, Nothing}

Return a `sign!` closure `(::HTTP.Request) -> Nothing` that pushes a fresh
`Authorization` header onto each request, suitable for
`GoogleApiCore.do_request_with_retry`/`service_request`. Returns `nothing` when
no authentication is needed — i.e. `creds === nothing` or `is_emulator=true` —
which the retry layer treats as "send unsigned".

The closure calls [`authorization_header`](@ref) on every invocation, so a
`CachedCredentials` source refreshes its token transparently across retries.
"""
function make_signer(creds::Union{Credentials, Nothing}; is_emulator::Bool=false)
    (is_emulator || creds === nothing) && return nothing
    return req -> push!(req.headers, authorization_header(creds))
end
