# GoogleAuth.jl

Authentication primitives for the Google Cloud Platform. Part of the [GoogleCloud2.jl](../README.md) monorepo.

## Features

- **Application Default Credentials (ADC)** — same lookup chain as `gcloud`/Python `google-auth`.
- **Service account JWT** flow (no GCP metadata needed).
- **GCE metadata server** integration for credentials on Compute Engine / Cloud Run / GKE.
- **OAuth 2.0 PKCE installed-app flow** — opens a browser, captures the redirect, exchanges the code.
- **Auto-refreshing token cache** (`CachedCredentials`) — refreshes 5 min before `expires_in` lapses, thread-safe.

## Quick start

```julia
using GoogleAuth

# Application Default Credentials (env var, well-known file, or metadata server)
creds = get_application_default()
token = get_token(creds)        # Token(access_token, expires_in, token_type)

# Use with any HTTP request that expects "Authorization: Bearer <token>"
header = authorization_header(creds)   # => "Authorization" => "Bearer ya29.xxx"
```

## Browser-based OAuth (installed app)

```julia
creds = authorize_via_browser(;
    client_id     = "your-client-id.apps.googleusercontent.com",
    client_secret = "your-client-secret",
    scopes        = ["https://www.googleapis.com/auth/cloud-platform"],
    open_browser  = true,         # set false to print the URL instead
    save_adc      = false,        # set true to persist to gcloud's well-known path
)
```

The flow:

1. Starts a one-shot HTTP server on `127.0.0.1:<random-port>`.
2. Opens Google's authorization endpoint with PKCE (S256) and a CSRF state token.
3. Waits for the redirect, validates `state`, extracts the `code`.
4. Exchanges the code for `access_token` + `refresh_token` at the token endpoint.
5. Wraps the result in `CachedCredentials`.

### `save_adc=true` warning

The refresh token is written **in plaintext** to `~/.config/gcloud/application_default_credentials.json`. Anyone who can read that file can use your credentials. Default is `false` (memory only).

## Credential types

| Type | When to use |
|------|-------------|
| `UserCredentials` | OAuth user credentials (typically with refresh token) |
| `ServiceAccountCredentials` | Service account JSON key |
| `ComputeCredentials` | GCE/GKE/Cloud Run metadata server |
| `CachedCredentials` | Wraps any of the above; cached + auto-refresh |

## License

[MIT](LICENSE)
