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
    should_retry(method, status; idempotent=false) -> Bool

Determines if a given HTTP request should be retried based on the method and
status code. Only 429 and 5xx responses are retryable. GET and PUT are always
safe to retry; POST (and other methods) are retried only when the caller
declares the request `idempotent` (e.g. Pub/Sub `pull`/`acknowledge`).
"""
function should_retry(method::String, status::Integer; idempotent::Bool=false)
    # Retry on 5xx or 429 Too Many Requests
    if status == 429 || (500 <= status < 600)
        if method == "GET" || method == "PUT" || idempotent
            return true
        end
    end
    return false
end

"""
    _retry_delay(config, attempt, retry_after) -> Float64

Compute the sleep time before the next attempt. When the server sent a
`Retry-After` header with a non-negative integer number of seconds, that value
(capped at `config.max_delay`) takes precedence over the computed exponential
backoff. HTTP-date `Retry-After` values are not parsed and fall back to
backoff. A 10% random jitter is added in both cases.
"""
function _retry_delay(config::RetryConfig, attempt::Int,
                      retry_after::Union{Nothing, AbstractString})
    delay = min(config.initial_delay * (config.multiplier ^ (attempt - 1)), config.max_delay)
    if retry_after !== nothing
        secs = tryparse(Int, strip(retry_after))
        if secs !== nothing && secs >= 0
            delay = min(Float64(secs), config.max_delay)
        end
    end
    return delay + rand() * 0.1 * delay
end

"""
    do_request_with_retry(method, url, headers, body; config, sign!, idempotent, kwargs...)

Execute an HTTP request with exponential backoff and jitter.

The optional `sign!` argument is a function `(::HTTP.Request) -> Nothing` that
mutates the request in-place before each attempt — use it to inject auth
headers (e.g. `req -> CloudBase.GCP.gcpsign!(req; credentials=creds)`).
The request object is rebuilt from scratch on every retry so that a refreshed
token is used automatically.

`idempotent=true` declares that repeating this request is safe, which enables
retry of 429/5xx responses for methods other than GET/PUT (notably POST).
A `Retry-After` header with an integer number of seconds is honoured (capped
at `config.max_delay`).
"""
function do_request_with_retry(method::String, url::String, headers=[], body="";
                                config::RetryConfig=RetryConfig(),
                                sign! = nothing,
                                idempotent::Bool=false,
                                kwargs...)
    body_bytes = body isa AbstractString ? Vector{UInt8}(codeunits(body)) : body
    attempt = 0
    while true
        attempt += 1

        req = HTTP.Request(method, url, copy(headers), copy(body_bytes))
        sign! !== nothing && sign!(req)
        resp = HTTP.request(req.method, req.target, req.headers, req.body;
                            status_exception=false, kwargs...)

        if attempt >= config.max_attempts ||
           !should_retry(method, resp.status; idempotent=idempotent)
            if resp.status == 401 || resp.status == 403
                throw(AuthError(_parse_api_error_body(resp.body, resp.status)))
            elseif resp.status == 404
                throw(NotFoundError(url))
            elseif resp.status >= 400
                throw(GoogleAPIError(resp.status, _parse_api_error_body(resp.body, resp.status)))
            end
            return resp
        end

        retry_after = HTTP.header(resp, "Retry-After", "")
        sleep_time = _retry_delay(config, attempt,
                                  isempty(retry_after) ? nothing : retry_after)

        @debug "Request failed with status $(resp.status). Retrying in $(round(sleep_time, digits=2)) seconds..." attempt max_attempts = config.max_attempts
        sleep(sleep_time)
    end
end
