# [Core Library](@id core)

`GoogleApiCore` provides shared infrastructure used by all service packages:
HTTP retry with exponential back-off, AIP-158 pagination, and long-running
operation (LRO) support.

## HTTP Retry

```@docs
GoogleApiCore.RetryConfig
GoogleApiCore.do_request_with_retry
```

### Example

```julia
import GoogleApiCore

cfg = GoogleApiCore.RetryConfig(max_attempts=3, initial_delay=0.5)
resp = GoogleApiCore.do_request_with_retry("GET", "https://example.com/api"; config=cfg)
```

## Pagination

```@docs
GoogleApiCore.AbstractPage
GoogleApiCore.PagedIterator
GoogleApiCore.get_items
GoogleApiCore.get_next_token
```

### Example — custom page type

```julia
import GoogleApiCore

struct MyPage <: GoogleApiCore.AbstractPage
    items::Vector{String}
    next_page_token::Union{String,Nothing}
end

GoogleApiCore.get_items(p::MyPage)      = p.items
GoogleApiCore.get_next_token(p::MyPage) = p.next_page_token

iter = GoogleApiCore.PagedIterator() do token
    # call your API here, return a MyPage
end

for item in iter
    println(item)
end
```

## Exceptions

Service packages throw these typed exceptions instead of bare `error()` strings,
so callers can catch specific failure categories:

```@docs
GoogleApiCore.GoogleAPIError
GoogleApiCore.AuthError
GoogleApiCore.NotFoundError
```

### Example

```julia
import GoogleApiCore

try
    GoogleApiCore.do_request_with_retry("GET", "https://storage.googleapis.com/...")
catch e
    if e isa GoogleApiCore.NotFoundError
        println("Object does not exist: ", e.resource)
    elseif e isa GoogleApiCore.AuthError
        println("Auth failure — check credentials")
    elseif e isa GoogleApiCore.GoogleAPIError
        println("API error $(e.status): ", e.message)
    else
        rethrow(e)
    end
end
```

## Long-Running Operations

```@docs
GoogleApiCore.LROperation
GoogleApiCore.wait_for_operation
GoogleApiCore.cancel_operation
```
