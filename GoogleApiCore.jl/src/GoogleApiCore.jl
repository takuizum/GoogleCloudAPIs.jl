module GoogleApiCore

using HTTP
using JSON
using URIs

export RetryConfig, do_request_with_retry
export PagedIterator, AbstractPage, get_items, get_next_token
export Discovery
export LROperation, wait_for_operation, cancel_operation, LROClient
export GoogleAPIError, AuthError, NotFoundError, TimeoutError
export resolve_endpoint, service_request

include("exceptions.jl")
include("retry.jl")
include("pagination.jl")
include("client.jl")
include("discovery.jl")
include("lro.jl")

end # module GoogleApiCore
