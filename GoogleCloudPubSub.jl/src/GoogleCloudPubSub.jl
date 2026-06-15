module GoogleCloudPubSub

using HTTP
using JSON
import Base64

import GoogleAuth
import GoogleApiCore

export PubSubClient, Topic, Subscription, PubSubMessage
export create_topic, delete_topic, get_topic, list_topics, exists
export publish
export create_subscription, delete_subscription, get_subscription, list_subscriptions
export pull, acknowledge

"""
    PubSubClient(; project, creds=nothing, endpoint=nothing)
    PubSubClient(project; creds=nothing, endpoint=nothing)

A Cloud Pub/Sub REST API client.

If `PUBSUB_EMULATOR_HOST` is set in the environment and `endpoint` is not
explicitly provided, the client targets the emulator with no authentication.
"""
struct PubSubClient
    project::String
    creds::Union{GoogleAuth.Credentials, Nothing}
    endpoint::String
    is_emulator::Bool
end

function PubSubClient(; project::String,
                       creds::Union{GoogleAuth.Credentials, Nothing}=nothing,
                       endpoint::Union{String, Nothing}=nothing)
    ep, is_emu = GoogleApiCore.resolve_endpoint(;
        emulator_host = get(ENV, "PUBSUB_EMULATOR_HOST", ""),
        explicit      = endpoint,
        production    = "https://pubsub.googleapis.com")
    resolved = is_emu ? nothing : (creds === nothing ? GoogleAuth.get_application_default() : creds)
    return PubSubClient(project, resolved, ep, is_emu)
end

# Backwards-compat positional shim for the workflow example
PubSubClient(project::AbstractString; kwargs...) = PubSubClient(; project=String(project), kwargs...)

function _request(client::PubSubClient, method::String, path::AbstractString;
                  query=nothing, body=nothing, content_type=nothing,
                  idempotent::Bool=false, kwargs...)
    return GoogleApiCore.service_request(method, client.endpoint, path;
        query=query, body=body, content_type=content_type,
        sign! = GoogleAuth.make_signer(client.creds; is_emulator=client.is_emulator),
        idempotent=idempotent, kwargs...)
end

include("topics.jl")
include("messages.jl")
include("subscriptions.jl")

end # module GoogleCloudPubSub
