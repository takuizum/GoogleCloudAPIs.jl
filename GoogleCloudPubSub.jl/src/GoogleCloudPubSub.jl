module GoogleCloudPubSub

using HTTP
using JSON3
using StructTypes
using URIs
import Base64

import GoogleAuth
import GoogleApiCore

export PubSubClient, Topic, Subscription, PubSubMessage
export create_topic, delete_topic, get_topic, list_topics, exists
export publish
export create_subscription, delete_subscription, get_subscription, list_subscriptions
export pull, acknowledge

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

function _headers(client::PubSubClient; content_type=nothing)
    h = Pair{String, String}[]
    if !client.is_emulator && client.creds !== nothing
        push!(h, GoogleAuth.authorization_header(client.creds))
    end
    if content_type !== nothing
        push!(h, "Content-Type" => content_type)
    end
    return h
end

function _request(client::PubSubClient, method::String, path::AbstractString;
                  query=nothing, body=nothing, content_type=nothing)
    url = "$(client.endpoint)/$(path)"
    if query !== nothing && !isempty(query)
        url *= "?" * URIs.escapeuri(query)
    end
    headers = _headers(client; content_type=content_type)
    payload = body === nothing ? "" : body
    return GoogleApiCore.do_request_with_retry(method, url, headers, payload)
end

include("topics.jl")
include("messages.jl")
include("subscriptions.jl")

end # module GoogleCloudPubSub
