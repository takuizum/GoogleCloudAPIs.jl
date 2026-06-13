# [Contributing](@id contributing)

This page is for maintainers and contributors. It covers the repository layout,
local development setup, and how AI assistance was used in this project.

## Repository layout

```
GoogleCloudAPIs.jl/
├── GoogleAuth.jl/          # Auth sub-package
│   ├── src/
│   └── test/
├── GoogleApiCore.jl/       # Shared HTTP/pagination infrastructure
├── GoogleCloudStorage.jl/  # GCS sub-package
├── GoogleBigQuery.jl/            # BigQuery sub-package
├── GoogleCloudPubSub.jl/   # Pub/Sub sub-package
├── docs/                   # Documenter.jl source
├── .github/workflows/      # CI (CI.yml, Docs.yml, TagBot.yml, CompatHelper.yml)
├── docker-compose.yml      # Local emulator stack
└── Project.toml            # Root dev environment (not a package itself)
```

Each sub-package is an independent Julia package with its own `Project.toml`,
`src/`, and `test/` directories. The root `Project.toml` is a dev-only
environment for running all tests from one place.

## Local development setup

```julia
# From the repo root
using Pkg
Pkg.develop([
    PackageSpec(path="GoogleAuth.jl"),
    PackageSpec(path="GoogleApiCore.jl"),
    PackageSpec(path="GoogleCloudStorage.jl"),
    PackageSpec(path="GoogleBigQuery.jl"),
    PackageSpec(path="GoogleCloudPubSub.jl"),
])
Pkg.instantiate()
```

## Running tests

**Unit and mock tests** (no emulators needed):

```julia
# Run all packages
Pkg.test("GoogleAuth")
Pkg.test("GoogleApiCore")
```

**Integration tests** (requires emulators):

```bash
docker compose up -d
```

Then run the relevant package test. The test suites auto-detect emulator env vars:

| Env var | Default | Package |
|---------|---------|---------|
| `STORAGE_EMULATOR_HOST` | `http://localhost:4443` | GoogleCloudStorage |
| `BIGQUERY_EMULATOR_HOST` | `http://localhost:9050` | BigQuery |
| `PUBSUB_EMULATOR_HOST` | `localhost:8085` | GoogleCloudPubSub |

If the env var is not set, each test suite attempts to start a Docker container
automatically and falls back to skipping integration tests if Docker is unavailable.

## Adding a new sub-package

1. Create `NewPackage.jl/` with the standard layout (`src/`, `test/`, `Project.toml`).
2. Add `GoogleApiCore` and `GoogleAuth` as deps if needed.
3. Add the package to the root `Project.toml` deps and the `Pkg.develop` lists in `CI.yml` and `docs/make.jl`.
4. Add a corresponding `docs/src/newpackage.md` and register it in `docs/make.jl`'s `pages`.
5. Add a test matrix entry in `CI.yml`.

## Release process

1. Bump `version` in the sub-package's `Project.toml`.
2. Push to `main`. TagBot creates the git tag automatically after the General
   registry PR merges.
3. Register with Registrator by commenting on any commit:
   ```
   @JuliaRegistrator register subdir=NewPackage.jl
   ```

## AI-assisted development

This library was developed with significant assistance from
[Claude](https://claude.ai) (Anthropic). Per the
[Julia General Registry policy on LLM use](https://github.com/JuliaRegistries/General#is-there-any-policy-regarding-the-use-of-llms-in-registered-packages),
the following areas had substantial AI involvement:

| Area | LLM involvement |
|------|----------------|
| Package architecture | Monorepo structure and sub-package separation were designed with AI assistance |
| Source code (`src/`) | All implementation files were co-written with Claude; logic was reviewed and tested by the human author |
| Test suites (`test/`) | Mock HTTP server approach and test case design were AI-generated; integration tests were verified against real emulators |
| CI/CD | GitHub Actions workflows, emulator health checks, and CompatHelper / TagBot setup were generated with AI assistance |
| Documentation | Initial docstrings and this documentation were AI-drafted and edited by the human author |

All generated code has been read, understood, and validated by the human
maintainer through CI, emulator integration tests, and manual testing against
real GCP services.
