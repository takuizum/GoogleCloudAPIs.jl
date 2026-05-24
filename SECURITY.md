# Security Policy

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.
Report them privately via GitHub's [Security Advisories](../../security/advisories/new) feature.
We aim to respond within 5 business days.

## Known Design Trade-offs

This section documents the security properties of each authentication path and
the mitigations in place. It is intended for users who need to reason about
the risk profile of their deployment.

### SEC-001 — Credential display safety

All credential types (`ServiceAccountCredentials`, `UserCredentials`, `Token`,
`CachedCredentials`) override `Base.show` to redact secrets.  Private keys,
client secrets, refresh tokens, and access tokens are replaced with
`<redacted>` in REPL output and log messages.

The Julia REPL prints the value of the last expression in a cell. To suppress
display, end the line with `;` or assign to a variable before the session ends:

```julia
creds = get_application_default();   # trailing ; suppresses REPL output
```

### SEC-002 — Error message sanitization

HTTP error responses from Google Cloud APIs are parsed and only the
`error.code`, `error.message`, and `error.status` fields are included in
exception messages. Raw response bodies are not surfaced.

### SEC-003 — Plaintext refresh token on disk (`save_adc=true`)

`authorize_via_browser(save_adc=true)` writes the OAuth refresh token to the
[well-known ADC path](https://cloud.google.com/docs/authentication/application-default-credentials#personal):

- **Linux / macOS**: `~/.config/gcloud/application_default_credentials.json`
- **Windows**: `%APPDATA%\gcloud\application_default_credentials.json`

Mitigations already in place:

- The file is created with mode **0600** (owner read/write only) on
  POSIX systems, matching the behaviour of `gcloud auth application-default login`.
- A `@warn` message is emitted every time `save_adc=true` is used, explaining
  the risk.
- `save_adc` defaults to **false**; in-memory credentials are used unless
  persistence is explicitly requested.

**Residual risk**: any local process running as the same OS user can read the
file. A compromised refresh token grants indefinite access to GCP resources
until explicitly revoked at <https://myaccount.google.com/permissions>.

**Future work**: OS keychain integration (similar to the Python `keyring`
package or R's `keyring` package) is tracked as a potential improvement.
Until then, the recommended production path is to use a **service account**
(no refresh token on disk) or **Workload Identity Federation** (no long-lived
credential at all).

### SEC-004 — Local OAuth callback server

`authorize_via_browser` binds a one-shot HTTP server to `127.0.0.1` on a
randomly selected ephemeral port. This prevents external network access.

Mitigations already in place:

- A random port is chosen at runtime (not a fixed well-known port).
- The `state` parameter is validated on every callback to detect CSRF attempts.
- The server accepts at most one successful callback and then closes
  immediately.
- The default callback timeout is **60 seconds**; the server stops listening
  after that window.

**Residual risk**: another process running as the same OS user could
theoretically race to connect to the ephemeral port before the legitimate
browser redirect arrives. This is a low-probability, local-only attack. PKCE
(`code_challenge` / `code_verifier`) ensures that a stolen authorization code
cannot be exchanged for a token without the verifier held in memory.
