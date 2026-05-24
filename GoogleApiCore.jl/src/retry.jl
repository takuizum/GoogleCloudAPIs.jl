# retry.jl

"""
    RetryConfig(; initial_delay=1.0, multiplier=2.0, max_delay=60.0, max_attempts=5)

Configuration for exponential-backoff retry behaviour.

| Field | Default | Meaning |
|-------|---------|---------|
| `initial_delay` | `1.0` | Seconds before the first retry |
| `multiplier` | `2.0` | Delay multiplied by this on each subsequent attempt |
| `max_delay` | `60.0` | Upper bound on per-attempt sleep time |
| `max_attempts` | `5` | Maximum total attempts (including the first) |

A 10% random jitter is added to each delay to reduce thundering-herd effects.
"""
Base.@kwdef struct RetryConfig
    initial_delay::Float64 = 1.0
    multiplier::Float64 = 2.0
    max_delay::Float64 = 60.0
    max_attempts::Int = 5
end

"""
Determines if a given HTTP request should be retried based on the method and status code.
"""
function should_retry(method::String, status::Integer)
    # Retry on 5xx or 429 Too Many Requests
    if status == 429 || (500 <= status < 600)
        # GET and PUT are always safe to retry.
        # Note: POST is generally not idempotent and shouldn't be retried
        # automatically unless there is a precondition like if-generation-match.
        # This basic implementation retries GET and PUT.
        if method == "GET" || method == "PUT"
            return true
        end
    end
    return false
end

"""
    do_request_with_retry(method, url, headers, body; config, sign!, kwargs...)

Execute an HTTP request with exponential backoff and jitter.

The optional `sign!` argument is a function `(::HTTP.Request) -> Nothing` that
mutates the request in-place before each attempt — use it to inject auth
headers (e.g. `req -> CloudBase.GCP.gcpsign!(req; credentials=creds)`).
The request object is rebuilt from scratch on every retry so that a refreshed
token is used automatically.
"""
function do_request_with_retry(method::String, url::String, headers=[], body="";
                                config::RetryConfig=RetryConfig(),
                                sign! = nothing,
                                kwargs...)
    body_bytes = body isa AbstractString ? Vector{UInt8}(codeunits(body)) : body
    attempt = 0
    while true
        attempt += 1

        req = HTTP.Request(method, url, copy(headers), copy(body_bytes))
        sign! !== nothing && sign!(req)
        resp = HTTP.request(req.method, req.target, req.headers, req.body;
                            status_exception=false, kwargs...)

        if attempt >= config.max_attempts || !should_retry(method, resp.status)
            if resp.status == 401 || resp.status == 403
                throw(AuthError(_parse_api_error_body(resp.body, resp.status)))
            elseif resp.status == 404
                throw(NotFoundError(url))
            elseif resp.status >= 400
                throw(GoogleAPIError(resp.status, _parse_api_error_body(resp.body, resp.status)))
            end
            return resp
        end

        delay = min(config.initial_delay * (config.multiplier ^ (attempt - 1)), config.max_delay)
        jitter = rand() * 0.1 * delay
        sleep_time = delay + jitter

        @info "Request failed with status $(resp.status). Retrying in $(round(sleep_time, digits=2)) seconds..."
        sleep(sleep_time)
    end
end
