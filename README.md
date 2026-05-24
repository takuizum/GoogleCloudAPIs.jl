# GoogleCloudAPIs.jl

[![CI](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://takuizum.github.io/GoogleCloudAPIs.jl/stable)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Julia client libraries for Google Cloud Platform.

## Packages

| Package | Purpose |
|---------|---------|
| [GoogleAuth.jl](GoogleAuth.jl) | Authentication — ADC, service account, OAuth 2.0 |
| [BigQuery.jl](BigQuery.jl) | BigQuery — query, datasets, tables |
| [GoogleCloudStorage.jl](GoogleCloudStorage.jl) | Cloud Storage — buckets and objects |
| [GoogleCloudPubSub.jl](GoogleCloudPubSub.jl) | Pub/Sub — topics, subscriptions, publish/pull |

Each package can be installed independently. `GoogleApiCore` is a shared dependency pulled in automatically.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/takuizum/GoogleCloudAPIs.jl", subdir="BigQuery.jl")
Pkg.add(url="https://github.com/takuizum/GoogleCloudAPIs.jl", subdir="GoogleCloudStorage.jl")
Pkg.add(url="https://github.com/takuizum/GoogleCloudAPIs.jl", subdir="GoogleCloudPubSub.jl")
```

## Authentication

All clients use [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials) by default.

```bash
gcloud auth application-default login
```

Service account key files and browser-based OAuth are also supported — see [Authentication docs](https://takuizum.github.io/GoogleCloudAPIs.jl/stable/auth).

## Quick start

**BigQuery**

```julia
using BigQuery

bq   = BQClient("my-project")
rows = query(bq, "SELECT 1 AS n, 'hello' AS s")
rows[1].n  # 1
rows[1].s  # "hello"
```

**Cloud Storage**

```julia
using GoogleCloudStorage

gcs = Client("my-project")
upload_object(gcs, "my-bucket", "hello.txt", "Hello, World!")
bytes = download_object(gcs, "my-bucket", "hello.txt")
String(bytes)  # "Hello, World!"
```

**Pub/Sub**

```julia
using GoogleCloudPubSub

ps  = PubSubClient(project="my-project")
publish(ps, "my-topic", "hello")
msgs = pull(ps, "my-sub"; max_messages=10)
String(msgs[1].data)  # "hello"
```

For full API reference, see the [documentation](https://takuizum.github.io/GoogleCloudAPIs.jl/stable).

## Note on AI-assisted development

This library was developed with significant assistance from Claude (Anthropic). See [Contributing](https://takuizum.github.io/GoogleCloudAPIs.jl/stable/contributing) for details.

## License

[MIT](LICENSE)
