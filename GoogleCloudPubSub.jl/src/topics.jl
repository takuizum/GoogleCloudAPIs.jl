struct Topic
    name::String  # fully-qualified: "projects/{project}/topics/{id}"
end

_topic_path(client::PubSubClient, topic_id::AbstractString) =
    "v1/projects/$(client.project)/topics/$(topic_id)"

"""
    create_topic(client, topic_id) -> Topic

Create a topic in the configured project.
"""
function create_topic(client::PubSubClient, topic_id::AbstractString)
    resp = _request(client, "PUT", _topic_path(client, topic_id);
                    body="{}", content_type="application/json")
    doc = JSON3.read(resp.body)
    return Topic(String(get(doc, "name", "projects/$(client.project)/topics/$(topic_id)")))
end

"""
    get_topic(client, topic_id) -> Topic
"""
function get_topic(client::PubSubClient, topic_id::AbstractString)
    resp = _request(client, "GET", _topic_path(client, topic_id))
    doc = JSON3.read(resp.body)
    return Topic(String(doc["name"]))
end

"""
    delete_topic(client, topic_id) -> Nothing
"""
function delete_topic(client::PubSubClient, topic_id::AbstractString)
    _request(client, "DELETE", _topic_path(client, topic_id))
    return nothing
end

struct TopicListPage <: GoogleApiCore.AbstractPage
    items::Vector{Topic}
    next_page_token::Union{String, Nothing}
end

GoogleApiCore.get_items(p::TopicListPage) = p.items
GoogleApiCore.get_next_token(p::TopicListPage) = p.next_page_token

function _fetch_topic_page(client::PubSubClient, page_token::Union{Nothing, AbstractString})
    q = Dict{String, Any}()
    if page_token !== nothing && !isempty(page_token)
        q["pageToken"] = page_token
    end
    resp = _request(client, "GET", "v1/projects/$(client.project)/topics"; query=q)
    doc = JSON3.read(resp.body)
    raw = get(doc, "topics", nothing)
    items = raw === nothing ? Topic[] : [Topic(String(t["name"])) for t in raw]
    token = haskey(doc, "nextPageToken") ? String(doc["nextPageToken"]) : nothing
    return TopicListPage(items, token)
end

"""
    list_topics(client) -> PagedIterator{Topic}
"""
list_topics(client::PubSubClient) =
    GoogleApiCore.PagedIterator(token -> _fetch_topic_page(client, token))

"""
    exists(topic) -> Bool

Returns whether a `Topic` object has been resolved to a non-empty resource name.
"""
exists(topic::Topic) = !isempty(topic.name)
