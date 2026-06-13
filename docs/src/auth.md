# [Authentication](@id auth)

The `GoogleAuth` package implements Google Cloud authentication:

- **Application Default Credentials (ADC)** — reads `~/.config/gcloud/application_default_credentials.json`
- **Service Account JWT** — signs JWTs with an RSA private key from a JSON key file
- **Compute Engine metadata** — fetches tokens from the GCE metadata server
- **Browser OAuth 2.0** — PKCE installed-app flow for interactive use
- **Workload Identity Federation** — exchanges external OIDC tokens (e.g. GitHub Actions) for Google access tokens, keylessly

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
GoogleAuth.ExternalAccountCredentials
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

### Workload Identity Federation (GitHub Actions, keyless)

Workload Identity Federation lets CI systems authenticate to Google Cloud
without long-lived service account keys. With GitHub Actions, use the
[`google-github-actions/auth`](https://github.com/google-github-actions/auth)
action — it writes an `external_account` JSON file and sets
`GOOGLE_APPLICATION_CREDENTIALS`, so ADC just works:

```yaml
# .github/workflows/deploy.yml
permissions:
  id-token: write   # required for OIDC
  contents: read

steps:
  - uses: google-github-actions/auth@v2
    with:
      workload_identity_provider: projects/123/locations/global/workloadIdentityPools/pool/providers/github
      service_account: deploy@my-project.iam.gserviceaccount.com
  - run: julia my_script.jl   # get_application_default() picks up WIF automatically
```

```julia
import GoogleAuth

# Inside the workflow, no code changes are needed:
creds = GoogleAuth.get_application_default()
# creds isa CachedCredentials{ExternalAccountCredentials}
```

File- and url-sourced external credentials are supported (with optional JSON
field extraction). AWS and executable credential sources are not implemented.
