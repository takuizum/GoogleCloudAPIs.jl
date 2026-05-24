"""
    PubSubMessage

Represents a Pub/Sub message. Used both for publishing (only `data` and
`attributes` are sent) and for receiving (server populates `message_id`,
`publish_time`, and `ack_id`).
"""
struct PubSubMessage
    data::Vector{UInt8}
    attributes::Dict{String, String}
    message_id::Union{String, Nothing}
    publish_time::Union{String, Nothing}
    ack_id::Union{String, Nothing}
end

PubSubMessage(data::AbstractVector{UInt8}; attributes::AbstractDict=Dict{String,String}()) =
    PubSubMessage(Vector{UInt8}(data), Dict{String,String}(attributes), nothing, nothing, nothing)

PubSubMessage(data::AbstractString; attributes::AbstractDict=Dict{String,String}()) =
    PubSubMessage(Vector{UInt8}(data), Dict{String,String}(attributes), nothing, nothing, nothing)

function _message_to_json(msg::PubSubMessage)
    d = Dict{String, Any}("data" => Base64.base64encode(msg.data))
    if !isempty(msg.attributes)
        d["attributes"] = msg.attributes
    end
    return d
end

"""
    publish(client, topic_id, data) -> String
    publish(client, topic_id, messages::Vector{PubSubMessage}) -> Vector{String}

Publish one or more messages to a topic. Returns the message ID(s) assigned
by the server.

`data` may be a `Vector{UInt8}`, an `AbstractString`, or a `PubSubMessage`.
The single-message variants return a single message ID as `String`.
"""
function publish(client::PubSubClient, topic_id::AbstractString,
                 messages::Vector{PubSubMessage})
    isempty(messages) && return String[]
    body = JSON.json(Dict("messages" => [_message_to_json(m) for m in messages]))
    path = _topic_path(client, topic_id) * ":publish"
    resp = _request(client, "POST", path; body=body, content_type="application/json")
    doc = JSON.parse(IOBuffer(resp.body))
    ids = get(doc, "messageIds", nothing)
    return ids === nothing ? String[] : [String(x) for x in ids]
end

function publish(client::PubSubClient, topic_id::AbstractString, msg::PubSubMessage)
    ids = publish(client, topic_id, [msg])
    return isempty(ids) ? "" : ids[1]
end

publish(client::PubSubClient, topic_id::AbstractString, data::AbstractVector{UInt8};
        attributes::AbstractDict=Dict{String,String}()) =
    publish(client, topic_id, PubSubMessage(data; attributes=attributes))

publish(client::PubSubClient, topic_id::AbstractString, data::AbstractString;
        attributes::AbstractDict=Dict{String,String}()) =
    publish(client, topic_id, PubSubMessage(data; attributes=attributes))

function _parse_pull_message(received)
    msg = received["message"]
    data_b64 = String(get(msg, "data", ""))
    data = isempty(data_b64) ? UInt8[] : Base64.base64decode(data_b64)
    attrs_raw = get(msg, "attributes", nothing)
    attrs = Dict{String, String}()
    if attrs_raw !== nothing
        for (k, v) in attrs_raw
            attrs[String(k)] = String(v)
        end
    end
    return PubSubMessage(
        data,
        attrs,
        haskey(msg, "messageId")   ? String(msg["messageId"])   : nothing,
        haskey(msg, "publishTime") ? String(msg["publishTime"]) : nothing,
        haskey(received, "ackId")  ? String(received["ackId"])  : nothing,
    )
end
