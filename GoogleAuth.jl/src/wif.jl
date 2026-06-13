# wif.jl
#
# Workload Identity Federation (external_account credentials).
#
# Exchanges an external identity token (e.g. a GitHub Actions OIDC token) for
# a Google access token via the Security Token Service (STS), optionally
# followed by service account impersonation. This is the standard keyless
# path for CI systems and other non-GCP workloads:
# https://cloud.google.com/iam/docs/workload-identity-federation

const _STS_TOKEN_ENDPOINT = "https://sts.googleapis.com/v1/token"
const _STS_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:token-exchange"
const _STS_REQUESTED_TOKEN_TYPE = "urn:ietf:params:oauth:token-type:access_token"

"""
    ExternalAccountCredentials <: Credentials

Workload Identity Federation credentials, loaded from an `external_account`
JSON configuration (such as the one written by `gcloud iam
workload-identity-pools create-cred-config` or the `google-github-actions/auth`
action).

`get_token` performs up to three steps:

1. Fetch the *subject token* from `credential_source` — either a local file
   (`"file"`) or an HTTP endpoint (`"url"`, with optional `headers`). When
   `format.type == "json"`, the token is extracted from the field named by
   `format.subject_token_field_name`; otherwise the raw content is used.
2. Exchange it for a Google access token at the STS endpoint (`token_url`).
3. When `service_account_impersonation_url` is present, call
   `generateAccessToken` to impersonate the target service account.

Only file- and url-sourced credentials are supported; AWS
(`environment_id`) and executable sources throw an error at construction.

Wrap in [`CachedCredentials`](@ref) for caching — `get_application_default()`
does this automatically when `GOOGLE_APPLICATION_CREDENTIALS` points at an
`external_account` file.
"""
struct ExternalAccountCredentials <: Credentials
    audience::String
    subject_token_type::String
    token_url::String
    credential_source::Dict{String, Any}
    service_account_impersonation_url::Union{String, Nothing}
    scopes::Vector{String}

    function ExternalAccountCredentials(audience::AbstractString,
                                        subject_token_type::AbstractString,
                                        token_url::AbstractString,
                                        credential_source::AbstractDict;
                                        service_account_impersonation_url::Union{AbstractString, Nothing}=nothing,
                                        scopes::AbstractVector{<:AbstractString}=String[])
        source = Dict{String, Any}(String(k) => v for (k, v) in credential_source)
        if haskey(source, "environment_id") || haskey(source, "executable")
            error("Unsupported credential_source for external_account: only " *
                  "file- and url-sourced credentials are implemented " *
                  "(AWS and executable sources are not).")
        end
        if !haskey(source, "file") && !haskey(source, "url")
            error("external_account credential_source must contain \"file\" or \"url\".")
        end
        new(String(audience), String(subject_token_type), String(token_url),
            source,
            service_account_impersonation_url === nothing ? nothing :
                String(service_account_impersonation_url),
            collect(String, scopes))
    end
end

function ExternalAccountCredentials(d::AbstractDict; scopes::AbstractVector{<:AbstractString}=String[])
    haskey(d, "audience") || error("external_account JSON is missing \"audience\"")
    haskey(d, "subject_token_type") || error("external_account JSON is missing \"subject_token_type\"")
    haskey(d, "credential_source") || error("external_account JSON is missing \"credential_source\"")
    return ExternalAccountCredentials(
        String(d["audience"]),
        String(d["subject_token_type"]),
        String(get(d, "token_url", _STS_TOKEN_ENDPOINT)),
        d["credential_source"];
        service_account_impersonation_url =
            haskey(d, "service_account_impersonation_url") ?
                String(d["service_account_impersonation_url"]) : nothing,
        scopes = scopes,
    )
end

function Base.show(io::IO, c::ExternalAccountCredentials)
    source_kind = haskey(c.credential_source, "file") ? "file" : "url"
    print(io, "ExternalAccountCredentials(audience=$(repr(c.audience)), " *
              "source=<$(source_kind)>, " *
              "impersonation=$(c.service_account_impersonation_url !== nothing))")
end

with_scopes(c::ExternalAccountCredentials, scopes::AbstractVector{<:AbstractString}) =
    ExternalAccountCredentials(c.audience, c.subject_token_type, c.token_url,
                               c.credential_source;
                               service_account_impersonation_url=c.service_account_impersonation_url,
                               scopes=scopes)

"""
    _fetch_subject_token(source::AbstractDict) -> String

Read the external identity token from a `credential_source` definition
(`"file"` or `"url"`, with optional JSON field extraction via `format`).
"""
function _fetch_subject_token(source::AbstractDict)
    content = if haskey(source, "file")
        path = String(source["file"])
        isfile(path) || error("Subject token file not found: $path")
        read(path, String)
    else
        url = String(source["url"])
        headers = Pair{String, String}[]
        if haskey(source, "headers") && source["headers"] isa AbstractDict
            for (k, v) in source["headers"]
                push!(headers, String(k) => String(v))
            end
        end
        resp = HTTP.get(url, headers; status_exception=false)
        resp.status == 200 ||
            error("Failed to fetch subject token from credential_source URL: " *
                  "status=$(resp.status)")
        String(resp.body)
    end

    fmt = get(source, "format", nothing)
    if fmt isa AbstractDict && String(get(fmt, "type", "text")) == "json"
        field = String(fmt["subject_token_field_name"])
        doc = JSON.parse(content)
        haskey(doc, field) ||
            error("Subject token JSON does not contain field \"$field\"")
        return String(doc[field])
    end
    return strip(content)
end

"""
    _sts_exchange(creds, subject_token) -> Token

Exchange the subject token for a Google access token at the STS endpoint
(RFC 8693 token exchange).
"""
function _sts_exchange(creds::ExternalAccountCredentials, subject_token::AbstractString)
    # When impersonation follows, the STS token only needs the IAM scope;
    # the final scopes are requested in the generateAccessToken call.
    scope = if creds.service_account_impersonation_url !== nothing
        "https://www.googleapis.com/auth/cloud-platform"
    else
        isempty(creds.scopes) ? "https://www.googleapis.com/auth/cloud-platform" :
                                join(creds.scopes, " ")
    end

    body = URIs.escapeuri(Dict(
        "grant_type"           => _STS_GRANT_TYPE,
        "audience"             => creds.audience,
        "subject_token"        => String(subject_token),
        "subject_token_type"   => creds.subject_token_type,
        "requested_token_type" => _STS_REQUESTED_TOKEN_TYPE,
        "scope"                => scope,
    ))
    headers = ["Content-Type" => "application/x-www-form-urlencoded"]

    resp = HTTP.post(creds.token_url, headers, body; status_exception=false)
    if resp.status != 200
        # Never echo the subject token: only the sanitized server message.
        error("STS token exchange failed: " *
              _parse_google_error_body(resp.body, resp.status))
    end
    j = JSON.parse(IOBuffer(resp.body))
    return Token(String(j["access_token"]),
                 Int(get(j, "expires_in", 3600)),
                 String(get(j, "token_type", "Bearer")))
end

function get_token(creds::ExternalAccountCredentials)
    subject_token = _fetch_subject_token(creds.credential_source)
    sts_token = _sts_exchange(creds, subject_token)

    creds.service_account_impersonation_url === nothing && return sts_token

    scopes = isempty(creds.scopes) ?
        ["https://www.googleapis.com/auth/cloud-platform"] : creds.scopes
    return _generate_access_token(creds.service_account_impersonation_url,
                                  sts_token.access_token, scopes, 3600;
                                  error_prefix="Failed to impersonate via $(creds.service_account_impersonation_url)")
end
