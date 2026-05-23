using Documenter

# We push the subdirectories to LOAD_PATH to allow Documenter to find them
push!(LOAD_PATH, "../GoogleApiCore.jl", "../GoogleAuth.jl", "../GoogleCloudStorage.jl", "../BigQuery.jl", "../GoogleCloudPubSub.jl")

using GoogleApiCore
using GoogleAuth
using GoogleCloudStorage
using BigQuery
using GoogleCloudPubSub

makedocs(
    sitename = "GoogleCloud2.jl",
    format = Documenter.HTML(),
    modules = [GoogleApiCore, GoogleAuth, GoogleCloudStorage, BigQuery, GoogleCloudPubSub],
    pages = [
        "Home" => "index.md",
        "Authentication" => "auth.md",
        "Core Library" => "core.md",
        "Storage API" => "storage.md",
        "BigQuery API" => "bigquery.md",
        "PubSub API" => "pubsub.md"
    ]
)
