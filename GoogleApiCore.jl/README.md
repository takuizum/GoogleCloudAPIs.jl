# GoogleApiCore.jl


[![CI](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml) [![codecov](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)

Shared infrastructure for Google Cloud REST API clients. Part of the [GoogleCloudAPIs.jl](../README.md) monorepo.

This package contains the cross-cutting concerns that every Google API client needs but should not re-implement:

- HTTP retry with exponential backoff + jitter
- AIP-158 page iteration
- Long-running operation polling

It is intentionally credential-agnostic — callers either inject an `Authorization` header directly or pass a `sign!` callback to add one per attempt.

## Retry

```julia
using GoogleApiCore

resp = do_request_with_retry("GET", "https://example.googleapis.com/v1/foo",
                              ["Authorization" => "Bearer ..."], "";
                              config = RetryConfig(max_attempts=5))
```

- Retries on `5xx` and `429` responses, plus network errors.
- Exponential backoff: 1s, 2s, 4s, 8s, ... up to `max_delay`.
- Accepts a `sign!` kwarg of type `req::HTTP.Request -> Nothing` for per-attempt header injection.

## Pagination

Implement `AbstractPage` for any list-style API:

```julia
import GoogleApiCore: AbstractPage, get_items, get_next_token, PagedIterator

struct MyPage <: AbstractPage
    items::Vector{Foo}
    next_page_token::Union{String, Nothing}
end
get_items(p::MyPage)      = p.items
get_next_token(p::MyPage) = p.next_page_token

iter = PagedIterator(token -> fetch_my_page(token))
for foo in iter            # transparently follows nextPageToken
    @show foo
end
```

## Long-running operations

```julia
op = LROperation("operations/abc", false, nothing, nothing)
result = poll(op, status_fn; poll_interval=2.0, timeout=600)
```

## License

[MIT](LICENSE)
