# exceptions.jl

"""
    GoogleAPIError(status, message)

Raised when a Google Cloud REST API returns an HTTP error status (4xx / 5xx).

Fields:
- `status::Int`    — HTTP status code
- `message::String` — error body / description
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
