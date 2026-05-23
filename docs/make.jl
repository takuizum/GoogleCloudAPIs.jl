using Documenter

# Add all sub-package src directories to LOAD_PATH so Documenter can find them.
for pkg in ("GoogleAuth", "GoogleApiCore", "GoogleCloudStorage", "BigQuery", "GoogleCloudPubSub")
    push!(LOAD_PATH, joinpath(@__DIR__, "..", "$(pkg).jl", "src"))
end

using GoogleAuth
using GoogleApiCore
using GoogleCloudStorage
using BigQuery
using GoogleCloudPubSub

makedocs(
    sitename = "GoogleCloudAPIs.jl",
    format   = Documenter.HTML(
        prettyurls        = get(ENV, "CI", nothing) == "true",
        repolink          = "https://github.com/takuizum/GoogleCloudAPIs.jl",
        inventory_version = "0.1.0",
    ),
    modules  = [GoogleAuth, GoogleApiCore, GoogleCloudStorage, BigQuery, GoogleCloudPubSub],
    checkdocs = :none,
    # Disable remote source links when no git remote is configured (local builds).
    remotes  = nothing,
    pages = [
        "Home"           => "index.md",
        "Authentication" => "auth.md",
        "Core Library"   => "core.md",
        "Cloud Storage"  => "storage.md",
        "BigQuery"       => "bigquery.md",
        "Cloud Pub/Sub"  => "pubsub.md",
    ],
)

# deploydocs is a no-op locally (no GITHUB_TOKEN / DOCUMENTER_KEY).
deploydocs(
    repo      = "github.com/takuizum/GoogleCloudAPIs.jl.git",
    devbranch = "main",
)
