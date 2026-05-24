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
        j = JSON3.read(body_str)
        if haskey(j, :error)
            e = j.error
            if e isa JSON3.Object
                code = get(e, :code, status)
                msg  = get(e, :message, "unknown error")
                st   = string(get(e, :status, ""))
                return isempty(st) ? "status=$code: $msg" : "status=$code ($st): $msg"
            elseif e isa AbstractString
                desc = string(get(j, :error_description, ""))
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
