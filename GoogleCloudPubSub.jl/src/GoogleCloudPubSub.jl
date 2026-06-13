module GoogleCloudPubSub

using HTTP
using JSON
using URIs
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
    if endpoint === nothing
        emulator_host = get(ENV, "PUBSUB_EMULATOR_HOST", "")
        if !isempty(emulator_host)
            ep = startswith(emulator_host, "http") ? emulator_host : "http://$(emulator_host)"
            return PubSubClient(project, nothing, ep, true)
        end
        resolved = creds === nothing ? GoogleAuth.get_application_default() : creds
        return PubSubClient(project, resolved, "https://pubsub.googleapis.com", false)
    end
    is_emu = startswith(endpoint, "http://")
    resolved = is_emu ? nothing : (creds === nothing ? GoogleAuth.get_application_default() : creds)
    return PubSubClient(project, resolved, endpoint, is_emu)
end

# Backwards-compat positional shim for the workflow example
PubSubClient(project::AbstractString; kwargs...) = PubSubClient(; project=String(project), kwargs...)

function _headers(; content_type=nothing)
    h = Pair{String, String}[]
    if content_type !== nothing
        push!(h, "Content-Type" => content_type)
    end
    return h
end

function _make_signer(client::PubSubClient)
    if client.is_emulator || client.creds === nothing
        return nothing
    end
    creds = client.creds
    return req -> push!(req.headers, GoogleAuth.authorization_header(creds))
end

function _request(client::PubSubClient, method::String, path::AbstractString;
                  query=nothing, body=nothing, content_type=nothing,
                  idempotent::Bool=false)
    url = "$(client.endpoint)/$(path)"
    if query !== nothing && !isempty(query)
        url *= "?" * URIs.escapeuri(query)
    end
    headers = _headers(; content_type=content_type)
    payload = body === nothing ? "" : body
    return GoogleApiCore.do_request_with_retry(method, url, headers, payload;
                                               sign! = _make_signer(client),
                                               idempotent=idempotent)
end

include("topics.jl")
include("messages.jl")
include("subscriptions.jl")

end # module GoogleCloudPubSub
