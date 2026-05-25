# [Authentication](@id auth)

The `GoogleAuth` package implements Google Cloud authentication:

- **Application Default Credentials (ADC)** — reads `~/.config/gcloud/application_default_credentials.json`
- **Service Account JWT** — signs JWTs with an RSA private key from a JSON key file
- **Compute Engine metadata** — fetches tokens from the GCE metadata server
- **Browser OAuth 2.0** — PKCE installed-app flow for interactive use

All credential types share the [`Credentials`](@ref) abstract interface and are
automatically wrapped in [`CachedCredentials`](@ref) for token caching.

## Types

```@docs
GoogleAuth.Credentials
GoogleAuth.Token
GoogleAuth.UserCredentials
GoogleAuth.ServiceAccountCredentials
GoogleAuth.ComputeCredentials
GoogleAuth.CachedCredentials
```

## Functions

```@docs
GoogleAuth.get_application_default
GoogleAuth.get_token
GoogleAuth.authorization_header
GoogleAuth.authorize_via_browser
```

## Examples

### ADC (most common)

```julia
import GoogleAuth

creds = GoogleAuth.get_application_default()
token = GoogleAuth.get_token(creds)
println(token.token_type)   # "Bearer"
```

### Service Account

```julia
import JSON, GoogleAuth

sa = GoogleAuth.ServiceAccountCredentials(JSON.parse(read("key.json", String)))
creds = GoogleAuth.CachedCredentials(sa)
```

### Browser (interactive / installed-app)

```julia
import GoogleAuth

# Opens the browser for the user to log in; credentials are returned in memory.
creds = GoogleAuth.authorize_via_browser()
```
