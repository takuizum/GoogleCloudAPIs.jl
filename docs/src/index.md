# GoogleCloudAPIs.jl

A pure-Julia, high-performance client library for Google Cloud Platform.

## Packages

| Package | Description |
|---------|-------------|
| [`GoogleAuth`](@ref auth) | Application Default Credentials, OAuth 2.0, Service Account JWT |
| [`GoogleApiCore`](@ref core) | Shared HTTP retry, AIP-158 pagination, LRO |
| [`GoogleCloudStorage`](@ref storage) | Cloud Storage JSON API (buckets & objects) |
| [`BigQuery`](@ref bigquery) | BigQuery REST API (query, datasets, tables) |
| [`GoogleCloudPubSub`](@ref pubsub) | Cloud Pub/Sub (topics, subscriptions, publish/pull) |

## Quick Start

```julia
using Pkg
Pkg.add(url="https://github.com/your-org/GoogleCloudAPIs.jl", subdir="GoogleAuth.jl")
Pkg.add(url="https://github.com/your-org/GoogleCloudAPIs.jl", subdir="BigQuery.jl")
```

Authenticate once with the Google Cloud CLI:

```bash
gcloud auth application-default login
```

Then in Julia:

```julia
import GoogleAuth
import BigQuery

creds = GoogleAuth.get_application_default()
bq    = BigQuery.BQClient("my-project"; creds=creds)
rows  = BigQuery.query(bq, "SELECT 1 AS x")
println(rows[1].x)  # 1
```

## Design Principles

- **Auth-first** — all clients accept explicit `creds` and default to ADC.
- **Emulator-friendly** — set `STORAGE_EMULATOR_HOST` / `BIGQUERY_EMULATOR_HOST` / `PUBSUB_EMULATOR_HOST` to target local emulators with no auth changes.
- **Lazy pagination** — list APIs return `PagedIterator`; pages are only fetched on demand.
- **Thread-safe credentials** — `CachedCredentials` caches tokens with a `ReentrantLock`.
