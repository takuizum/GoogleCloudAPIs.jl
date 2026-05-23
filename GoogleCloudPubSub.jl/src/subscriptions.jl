"""
    Subscription

A Cloud Pub/Sub pull subscription. Both `name` and `topic` are fully-qualified
resource names (`"projects/{project}/subscriptions/{id}"` and
`"projects/{project}/topics/{id}"` respectively).
"""
struct Subscription
    name::String   # fully-qualified: "projects/{project}/subscriptions/{id}"
    topic::String  # fully-qualified topic resource name
end

_subscription_path(client::PubSubClient, sub_id::AbstractString) =
    "v1/projects/$(client.project)/subscriptions/$(sub_id)"

"""
    create_subscription(client, subscription_id, topic_id; ack_deadline_seconds=10) -> Subscription

Create a pull subscription bound to `topic_id`.
"""
function create_subscription(client::PubSubClient, sub_id::AbstractString,
                              topic_id::AbstractString;
                              ack_deadline_seconds::Int=10)
    body = JSON3.write(Dict(
        "topic"              => "projects/$(client.project)/topics/$(topic_id)",
        "ackDeadlineSeconds" => ack_deadline_seconds,
    ))
    resp = _request(client, "PUT", _subscription_path(client, sub_id);
                    body=body, content_type="application/json")
    doc = JSON3.read(resp.body)
    return Subscription(
        String(get(doc, "name", "projects/$(client.project)/subscriptions/$(sub_id)")),
        String(get(doc, "topic", "projects/$(client.project)/topics/$(topic_id)")),
    )
end

"""
    get_subscription(client, subscription_id) -> Subscription
"""
function get_subscription(client::PubSubClient, sub_id::AbstractString)
    resp = _request(client, "GET", _subscription_path(client, sub_id))
    doc = JSON3.read(resp.body)
    return Subscription(String(doc["name"]), String(doc["topic"]))
end

"""
    delete_subscription(client, subscription_id) -> Nothing
"""
function delete_subscription(client::PubSubClient, sub_id::AbstractString)
    _request(client, "DELETE", _subscription_path(client, sub_id))
    return nothing
end

struct SubscriptionListPage <: GoogleApiCore.AbstractPage
    items::Vector{Subscription}
    next_page_token::Union{String, Nothing}
end

GoogleApiCore.get_items(p::SubscriptionListPage) = p.items
GoogleApiCore.get_next_token(p::SubscriptionListPage) = p.next_page_token

function _fetch_subscription_page(client::PubSubClient,
                                   page_token::Union{Nothing, AbstractString})
    q = Dict{String, Any}()
    if page_token !== nothing && !isempty(page_token)
        q["pageToken"] = page_token
    end
    resp = _request(client, "GET", "v1/projects/$(client.project)/subscriptions"; query=q)
    doc = JSON3.read(resp.body)
    raw = get(doc, "subscriptions", nothing)
    items = if raw === nothing
        Subscription[]
    else
        [Subscription(String(s["name"]), String(get(s, "topic", ""))) for s in raw]
    end
    token = haskey(doc, "nextPageToken") ? String(doc["nextPageToken"]) : nothing
    return SubscriptionListPage(items, token)
end

"""
    list_subscriptions(client) -> PagedIterator{Subscription}
"""
list_subscriptions(client::PubSubClient) =
    GoogleApiCore.PagedIterator(token -> _fetch_subscription_page(client, token))

"""
    pull(client, subscription_id; max_messages=10, return_immediately=true) -> Vector{PubSubMessage}

Pull up to `max_messages` messages from a subscription. Returned messages
include an `ack_id` field which must be passed to [`acknowledge`](@ref) to
permanently remove them from the subscription.
"""
function pull(client::PubSubClient, sub_id::AbstractString;
              max_messages::Int=10, return_immediately::Bool=true)
    body = JSON3.write(Dict(
        "maxMessages"       => max_messages,
        "returnImmediately" => return_immediately,
    ))
    path = _subscription_path(client, sub_id) * ":pull"
    resp = _request(client, "POST", path; body=body, content_type="application/json")
    doc = JSON3.read(resp.body)
    raw = get(doc, "receivedMessages", nothing)
    raw === nothing && return PubSubMessage[]
    return [_parse_pull_message(r) for r in raw]
end

"""
    acknowledge(client, subscription_id, ack_ids::Vector{<:AbstractString}) -> Nothing

Acknowledge one or more messages so the server stops redelivering them.
"""
function acknowledge(client::PubSubClient, sub_id::AbstractString,
                     ack_ids::Vector{<:AbstractString})
    isempty(ack_ids) && return nothing
    body = JSON3.write(Dict("ackIds" => collect(String, ack_ids)))
    path = _subscription_path(client, sub_id) * ":acknowledge"
    _request(client, "POST", path; body=body, content_type="application/json")
    return nothing
end

# Convenience: acknowledge a single message by passing the message itself.
function acknowledge(client::PubSubClient, sub_id::AbstractString,
                     msg::PubSubMessage)
    msg.ack_id === nothing && return nothing
    return acknowledge(client, sub_id, [msg.ack_id])
end
