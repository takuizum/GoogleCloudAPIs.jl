# GoogleCloudPubSub.jl

Google Cloud Pub/Sub client for Julia. Part of the [GoogleCloud2.jl](../README.md) monorepo.

## Features

- Topic CRUD: `create_topic`, `get_topic`, `delete_topic`, `list_topics`
- Subscription CRUD: `create_subscription`, `delete_subscription`, `list_subscriptions`
- Publish (single or batch) with attributes
- Pull subscriber with `acknowledge`
- Emulator support via `PUBSUB_EMULATOR_HOST`
- Built on top of `GoogleAuth.jl` + `GoogleApiCore.jl`

## Quick start

```julia
using GoogleCloudPubSub

client = PubSubClient(project="your-project-id")

# Topic + subscription
create_topic(client, "my-topic")
create_subscription(client, "my-sub", "my-topic"; ack_deadline_seconds=30)

# Publish
mid = publish(client, "my-topic", "hello, world!";
              attributes=Dict("source" => "julia"))

# Pull + acknowledge
msgs = pull(client, "my-sub"; max_messages=10)
for m in msgs
    println(String(m.data), " (attrs: ", m.attributes, ")")
end
acknowledge(client, "my-sub", [m.ack_id for m in msgs if m.ack_id !== nothing])
```

## Batch publishing

```julia
ids = publish(client, "my-topic", [
    PubSubMessage("event-1"; attributes=Dict("k" => "1")),
    PubSubMessage("event-2"; attributes=Dict("k" => "2")),
    PubSubMessage(UInt8[0xCA, 0xFE]),
])
@assert length(ids) == 3
```

## Emulator

```bash
docker run -d -p 8085:8085 \
  gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators \
  gcloud beta emulators pubsub start --host-port=0.0.0.0:8085

export PUBSUB_EMULATOR_HOST=localhost:8085
```

Then in Julia, no auth is required:

```julia
client = PubSubClient(project="test-project")    # detects PUBSUB_EMULATOR_HOST
```

## v0.1 limitations

- Pull-based subscriber only (no streaming pull, no push subscriptions).
- No publisher batching/flow control (manual batching via `publish(..., Vector{PubSubMessage})`).
- No ordering keys / dead-letter / filter expressions.

## License

[MIT](LICENSE)
