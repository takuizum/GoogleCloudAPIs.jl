module GoogleApiCore

using HTTP
using JSON3
using StructTypes

export RetryConfig, do_request_with_retry
export PagedIterator, AbstractPage, get_items, get_next_token
export Discovery
export LROperation, wait_for_operation, cancel_operation, LROClient

include("retry.jl")
include("pagination.jl")
include("discovery.jl")
include("lro.jl")

end # module GoogleApiCore
