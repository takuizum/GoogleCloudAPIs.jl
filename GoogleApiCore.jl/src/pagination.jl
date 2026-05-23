# pagination.jl

"""
Abstract type for API page responses.
A concrete subtype should implement a function to get the `next_page_token` and the items.
"""
abstract type AbstractPage end

"""
A Julia idiomatic iterator over a Google Cloud API that supports AIP-158 Pagination.

# Example
```julia
# get_items_api should take a page_token and return an AbstractPage
iterator = PagedIterator(page_token -> get_items_api(project, page_token))
for item in iterator
    println(item)
end
```
"""
struct PagedIterator{F}
    fetch_page::F
end

struct PagedIteratorState
    current_page::AbstractPage
    item_index::Int
end

# Example of how concrete page types could be structured:
# struct MyApiPage <: AbstractPage
#     items::Vector{MyItem}
#     next_page_token::Union{String, Nothing}
# end
# get_items(p::MyApiPage) = p.items
# get_next_token(p::MyApiPage) = p.next_page_token

# Fallback functions that concrete types should override
function get_items(page::AbstractPage)
    error("get_items not implemented for $(typeof(page))")
end

function get_next_token(page::AbstractPage)
    error("get_next_token not implemented for $(typeof(page))")
end

Base.IteratorSize(::Type{<:PagedIterator}) = Base.SizeUnknown()
Base.IteratorEltype(::Type{<:PagedIterator}) = Base.EltypeUnknown()

function Base.iterate(iter::PagedIterator)
    # Fetch the first page (no token)
    first_page = iter.fetch_page(nothing)
    items = get_items(first_page)
    
    if isempty(items)
        return nothing
    end
    
    # Return the first item and the state
    return items[1], PagedIteratorState(first_page, 2)
end

function Base.iterate(iter::PagedIterator, state::PagedIteratorState)
    items = get_items(state.current_page)
    
    if state.item_index <= length(items)
        # Still iterating over the current page
        return items[state.item_index], PagedIteratorState(state.current_page, state.item_index + 1)
    else
        # Reached the end of the current page, check for next page
        next_token = get_next_token(state.current_page)
        
        if next_token === nothing || isempty(next_token)
            return nothing # No more pages
        end
        
        # Fetch the next page
        next_page = iter.fetch_page(next_token)
        next_items = get_items(next_page)
        
        if isempty(next_items)
            return nothing
        end
        
        return next_items[1], PagedIteratorState(next_page, 2)
    end
end
