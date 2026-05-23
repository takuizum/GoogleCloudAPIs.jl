# [Cloud Pub/Sub API](@id pubsub)

`GoogleCloudPubSub` wraps the [Cloud Pub/Sub REST API](https://cloud.google.com/pubsub/docs/reference/rest).

## Client

```@docs
GoogleCloudPubSub.PubSubClient
```

### Emulator

Set `PUBSUB_EMULATOR_HOST=localhost:8085` (host:port, no scheme) before
constructing a `PubSubClient` and it will use plain HTTP with no authentication.

## Topics

```@docs
GoogleCloudPubSub.Topic
GoogleCloudPubSub.create_topic
GoogleCloudPubSub.get_topic
GoogleCloudPubSub.delete_topic
GoogleCloudPubSub.list_topics
GoogleCloudPubSub.exists
```

## Subscriptions

```@docs
GoogleCloudPubSub.Subscription
GoogleCloudPubSub.create_subscription
GoogleCloudPubSub.get_subscription
GoogleCloudPubSub.delete_subscription
GoogleCloudPubSub.list_subscriptions
```

## Messages

```@docs
GoogleCloudPubSub.PubSubMessage
GoogleCloudPubSub.publish
GoogleCloudPubSub.pull
GoogleCloudPubSub.acknowledge
```

## Example

```julia
import GoogleCloudPubSub

ps = GoogleCloudPubSub.PubSubClient(project="my-project")

# Topic lifecycle
topic = GoogleCloudPubSub.create_topic(ps, "my-topic")
println(topic.name)

# Subscription
sub = GoogleCloudPubSub.create_subscription(ps, "my-sub", "my-topic"; ack_deadline_seconds=30)

# Publish
mid = GoogleCloudPubSub.publish(ps, "my-topic", "Hello, Pub/Sub!")
println("Published: ", mid)

# Batch publish
ids = GoogleCloudPubSub.publish(ps, "my-topic", [
    GoogleCloudPubSub.PubSubMessage("msg-1"),
    GoogleCloudPubSub.PubSubMessage("msg-2"; attributes=Dict("priority" => "high")),
])

# Pull and acknowledge
msgs = GoogleCloudPubSub.pull(ps, "my-sub"; max_messages=10)
for m in msgs
    println(String(m.data), "  attrs=", m.attributes)
end
ack_ids = [m.ack_id for m in msgs if m.ack_id !== nothing]
GoogleCloudPubSub.acknowledge(ps, "my-sub", ack_ids)

# Clean up
GoogleCloudPubSub.delete_subscription(ps, "my-sub")
GoogleCloudPubSub.delete_topic(ps, "my-topic")
```
