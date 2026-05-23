# GoogleCloudAPIs.jl

[![CI](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://takuizum.github.io/GoogleCloudAPIs.jl/stable)
[![Docs dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://takuizum.github.io/GoogleCloudAPIs.jl/dev)
[![codecov](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Modern Julia client libraries for Google Cloud Platform, organized as a monorepo of focused sub-packages.

## Packages

| Package | Purpose |
|---------|---------|
| [GoogleAuth.jl](GoogleAuth.jl) | Authentication: ADC, service accounts, OAuth 2.0 PKCE browser flow |
| [GoogleApiCore.jl](GoogleApiCore.jl) | Shared infrastructure: retry, pagination, long-running operations |
| [BigQuery.jl](BigQuery.jl) | BigQuery REST API client (jobs, datasets, tables) |
| [GoogleCloudStorage.jl](GoogleCloudStorage.jl) | Cloud Storage JSON API client (buckets, objects) |
| [GoogleCloudPubSub.jl](GoogleCloudPubSub.jl) | Pub/Sub client (topics, subscriptions, publish/pull) |

## Design

- **Composable** — each sub-package can be added independently. No "umbrella" import.
- **Cred-agnostic** — every client accepts a `creds::GoogleAuth.Credentials` argument and falls back to Application Default Credentials.
- **Emulator-friendly** — `*_EMULATOR_HOST` env vars switch endpoints automatically (`BIGQUERY_EMULATOR_HOST`, `STORAGE_EMULATOR_HOST`, `PUBSUB_EMULATOR_HOST`).
- **Auto-refresh tokens** — `CachedCredentials` wraps any inner credential type and refreshes 5 min before expiry.

## Quick start

```julia
import Pkg
Pkg.develop(path="./GoogleAuth.jl")
Pkg.develop(path="./BigQuery.jl")

using BigQuery
client = BQClient("your-project-id")             # uses ADC by default
rows = query(client, "SELECT 1 AS n")
```

## Authentication

```julia
using GoogleAuth

# Option A: Application Default Credentials (gcloud auth application-default login)
creds = get_application_default()

# Option B: Browser-based OAuth (installed-app PKCE)
creds = authorize_via_browser(;
    client_id     = "...",
    client_secret = "...",
    scopes        = ["https://www.googleapis.com/auth/cloud-platform"],
)
```

## Status

v0.1 — REST APIs only. Future work:

- BigQuery Storage Read API (gRPC) for zero-copy Arrow streaming
- GCS resumable uploads & V4 signed URLs
- PubSub streaming pull / publisher batching

## License

[MIT](LICENSE)
