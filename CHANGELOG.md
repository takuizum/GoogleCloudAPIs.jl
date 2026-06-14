# Changelog

All notable changes to the packages in this monorepo are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the packages aim to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This is a monorepo of independently versioned packages
(`GoogleApiCore`, `GoogleAuth`, `GoogleBigQuery`, `GoogleCloudStorage`,
`GoogleCloudPubSub`). Entries are grouped by package.

## [Unreleased]

### GoogleApiCore
- `do_request_with_retry` / `should_retry` gained an `idempotent` keyword so callers
  can opt non-GET/PUT requests into 429/5xx retry.
- Integer `Retry-After` response headers are now honoured (capped at `max_delay`).
- Added `TimeoutError` for client-side deadlines.
- Retry log demoted from `@info` to `@debug`.

### GoogleAuth
- Added `ExternalAccountCredentials` — Workload Identity Federation
  (`external_account`) with file- and url-sourced subject tokens, STS token
  exchange, and optional service-account impersonation. ADC now dispatches
  `external_account` JSON automatically, enabling keyless GitHub Actions → GCP.

### GoogleBigQuery
- **Renamed from `BigQuery` to `GoogleBigQuery`** (UUID and all exported names
  unchanged; update `using`/`import` only).
- Full result type conversion: `TIMESTAMP`/`DATETIME` → `DateTime`, `DATE` → `Date`,
  `TIME` → `Time`, `BYTES` → `Vector{UInt8}`, `RECORD`/`STRUCT` → nested `NamedTuple`,
  `REPEATED` → `Vector`. `NUMERIC`/`BIGNUMERIC` are kept as lossless `String`s.
- Parameterized queries via `query(...; params=...)` (named `Dict` and positional
  `Vector`), guarding against SQL injection.
- `query` gained `poll_timeout` (default 600s) and no longer polls forever on a
  stuck job.

### Compatibility
- All packages widened JSON compat to `"0.21, 1"`.

## [0.1.0]

Initial release of the monorepo.

### GoogleApiCore
- Exponential-backoff retry with jitter (`RetryConfig`, `do_request_with_retry`).
- AIP-158 pagination (`PagedIterator`, `AbstractPage`).
- Sanitized error types (`GoogleAPIError`, `AuthError`, `NotFoundError`).

### GoogleAuth
- Application Default Credentials chain (env var → well-known file → metadata server).
- `ServiceAccountCredentials` (RS256 JWT), `UserCredentials` (refresh token),
  `ComputeCredentials` (metadata server), `ImpersonatedCredentials`.
- Thread-safe `CachedCredentials` with 5-minute pre-expiry refresh.
- Browser OAuth 2.0 installed-app flow with PKCE (`authorize_via_browser`).
- Secrets redacted in `Base.show` for all credential types.

### GoogleBigQuery
- `query` returning `Vector{NamedTuple}` (a Tables.jl row table) or `Arrow.Table`.
- Dataset and table CRUD.

### GoogleCloudStorage
- Bucket and object CRUD; simple upload/download; paginated listing.

### GoogleCloudPubSub
- Topic and subscription CRUD; publish (single/batch), pull, acknowledge.

[Unreleased]: https://github.com/takuizum/GoogleCloudAPIs.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/takuizum/GoogleCloudAPIs.jl/releases/tag/v0.1.0
