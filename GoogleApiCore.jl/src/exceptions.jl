# exceptions.jl

"""
    _parse_api_error_body(body, status) -> String

Extract a human-readable message from a Google Cloud API error response without
leaking the raw payload. Handles the standard REST error envelope
`{"error":{"code":…,"message":…,"status":…}}`.
"""
function _parse_api_error_body(body::Union{String, AbstractVector{UInt8}}, status::Integer)
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
    GoogleAPIError(status, message)

Raised when a Google Cloud REST API returns an HTTP error status (4xx / 5xx).

Fields:
- `status::Int`    — HTTP status code
- `message::String` — sanitized error description
"""
struct GoogleAPIError <: Exception
    status::Int
    message::String
end

Base.showerror(io::IO, e::GoogleAPIError) =
    print(io, "GoogleAPIError($(e.status)): $(e.message)")

"""
    AuthError(message)

Raised for authentication and authorization failures (e.g. invalid credentials,
missing token, or a 401/403 response from the API).
"""
struct AuthError <: Exception
    message::String
end

Base.showerror(io::IO, e::AuthError) = print(io, "AuthError: $(e.message)")

"""
    NotFoundError(resource)

Raised when the requested resource does not exist (HTTP 404).
"""
struct NotFoundError <: Exception
    resource::String
end

Base.showerror(io::IO, e::NotFoundError) =
    print(io, "NotFoundError: resource not found — $(e.resource)")

"""
    TimeoutError(operation, seconds)

Raised when a client-side deadline expires while waiting for a server-side
operation to complete (e.g. polling a BigQuery job or a long-running
operation).

Fields:
- `operation::String` — description of what was being waited on
- `seconds::Float64`  — the deadline that was exceeded, in seconds
"""
struct TimeoutError <: Exception
    operation::String
    seconds::Float64
end

Base.showerror(io::IO, e::TimeoutError) =
    print(io, "TimeoutError: $(e.operation) (waited $(e.seconds)s)")
