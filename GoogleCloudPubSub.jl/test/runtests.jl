using Test
using GoogleCloudPubSub
using HTTP
using JSON
using Aqua
import Base64
import Sockets
import GoogleAuth
import GoogleAuth: get_token

function free_port()
    srv = Sockets.listen(Sockets.localhost, 0)
    port = Sockets.getsockname(srv)[2]
    close(srv)
    return port
end

struct MockPSCreds <: GoogleAuth.Credentials end
get_token(::MockPSCreds) = GoogleAuth.Token("mock-ps-token", 3600, "Bearer")

@testset "GoogleCloudPubSub.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(GoogleCloudPubSub; ambiguities=false, persistent_tasks=false)
    end

    # ── PubSubMessage construction ──────────────────────────
    @testset "PubSubMessage helpers" begin
        m1 = PubSubMessage("hello")
        @test m1.data == Vector{UInt8}("hello")
        @test isempty(m1.attributes)
        @test m1.ack_id === nothing

        m2 = PubSubMessage(UInt8[0x01, 0x02]; attributes=Dict("k" => "v"))
        @test m2.data == UInt8[0x01, 0x02]
        @test m2.attributes["k"] == "v"
    end

    # ── publish single message (mock server) ─────────────────
    @testset "publish single message (mock)" begin
        port = free_port()
        received_body = Ref{Vector{UInt8}}()
        received_path = Ref{String}()
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            received_path[] = req.target
            HTTP.Response(200, ["Content-Type" => "application/json"],
                          JSON.json(Dict("messageIds" => ["mid-1"])))
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            mid = publish(client, "topic-a", "hello, world!")
            @test mid == "mid-1"
            @test occursin("/v1/projects/p/topics/topic-a:publish", received_path[])
            doc = JSON.parse(IOBuffer(received_body[]))
            @test length(doc["messages"]) == 1
            data_b64 = String(doc["messages"][1]["data"])
            @test String(Base64.base64decode(data_b64)) == "hello, world!"
        finally
            close(server)
        end
    end

    # ── publish batch with attributes (mock) ────────────────
    @testset "publish batch with attributes (mock)" begin
        port = free_port()
        received_body = Ref{Vector{UInt8}}()
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            HTTP.Response(200, ["Content-Type" => "application/json"],
                          JSON.json(Dict("messageIds" => ["m1", "m2"])))
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            msgs = [
                PubSubMessage("first";  attributes=Dict("k" => "1")),
                PubSubMessage("second"; attributes=Dict("k" => "2")),
            ]
            ids = publish(client, "topic-a", msgs)
            @test ids == ["m1", "m2"]
            doc = JSON.parse(IOBuffer(received_body[]))
            @test length(doc["messages"]) == 2
            @test String(doc["messages"][1]["attributes"]["k"]) == "1"
            @test String(Base64.base64decode(String(doc["messages"][2]["data"]))) == "second"
        finally
            close(server)
        end
    end

    # ── pull and acknowledge (mock) ─────────────────────────
    @testset "pull and acknowledge (mock)" begin
        port = free_port()
        recorded = Ref{Vector{String}}(String[])
        body_pull = JSON.json(Dict("receivedMessages" => [
            Dict(
                "ackId" => "ACK-1",
                "message" => Dict(
                    "data"        => Base64.base64encode("payload-1"),
                    "messageId"   => "msg-1",
                    "publishTime" => "2026-01-01T00:00:00.000Z",
                    "attributes"  => Dict("source" => "test"),
                ),
            ),
        ]))
        server = HTTP.serve!(port) do req
            push!(recorded[], "$(req.method) $(req.target)")
            if endswith(req.target, ":pull")
                return HTTP.Response(200, ["Content-Type" => "application/json"], body_pull)
            elseif endswith(req.target, ":acknowledge")
                # Verify ack_ids
                doc = JSON.parse(IOBuffer(req.body))
                @assert "ACK-1" in [String(x) for x in doc["ackIds"]]
                return HTTP.Response(200, "{}")
            end
            return HTTP.Response(404, "")
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            msgs = pull(client, "sub-a"; max_messages=5)
            @test length(msgs) == 1
            @test String(msgs[1].data) == "payload-1"
            @test msgs[1].message_id == "msg-1"
            @test msgs[1].ack_id == "ACK-1"
            @test msgs[1].attributes["source"] == "test"

            # Acknowledge by message
            acknowledge(client, "sub-a", msgs[1])
            @test any(s -> occursin(":pull",        s), recorded[])
            @test any(s -> occursin(":acknowledge", s), recorded[])
        finally
            close(server)
        end
    end

    # ── pull returns empty when no messages ─────────────────
    @testset "pull empty (mock)" begin
        port = free_port()
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], "{}")
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            @test isempty(pull(client, "sub-empty"))
        finally
            close(server)
        end
    end

    # ── transient 5xx: pull/acknowledge retry, publish does not ──
    @testset "pull retries on transient 500 (mock)" begin
        port = free_port()
        hits = Ref(0)
        server = HTTP.serve!(port) do _req
            hits[] += 1
            status = hits[] == 1 ? 500 : 200
            HTTP.Response(status, ["Content-Type" => "application/json"], "{}")
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            @test isempty(pull(client, "sub-retry"))
            @test hits[] == 2   # 500 → リトライ → 200
        finally
            close(server)
        end
    end

    @testset "acknowledge retries on transient 500 (mock)" begin
        port = free_port()
        hits = Ref(0)
        server = HTTP.serve!(port) do _req
            hits[] += 1
            status = hits[] == 1 ? 503 : 200
            HTTP.Response(status, ["Content-Type" => "application/json"], "{}")
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            @test acknowledge(client, "sub-retry", ["ACK-1"]) === nothing
            @test hits[] == 2
        finally
            close(server)
        end
    end

    @testset "publish does not retry on 500 (mock)" begin
        port = free_port()
        hits = Ref(0)
        server = HTTP.serve!(port) do _req
            hits[] += 1
            HTTP.Response(500, ["Content-Type" => "application/json"], "{}")
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            @test_throws Exception publish(client, "topic-x", "data")
            @test hits[] == 1   # 重複発行を避けるためリトライしない
        finally
            close(server)
        end
    end

    # ── Subscription CRUD (mock) ────────────────────────────
    @testset "create_subscription (mock)" begin
        port = free_port()
        received_body = Ref{Vector{UInt8}}()
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(Dict(
                "name"  => "projects/p/subscriptions/sub-x",
                "topic" => "projects/p/topics/topic-x",
            )))
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            sub = create_subscription(client, "sub-x", "topic-x"; ack_deadline_seconds=30)
            @test sub.name  == "projects/p/subscriptions/sub-x"
            @test sub.topic == "projects/p/topics/topic-x"
            doc = JSON.parse(IOBuffer(received_body[]))
            @test String(doc["topic"]) == "projects/p/topics/topic-x"
            @test Int(doc["ackDeadlineSeconds"]) == 30
        finally
            close(server)
        end
    end

    @testset "delete_subscription (mock)" begin
        port = free_port()
        received_method = Ref{String}()
        server = HTTP.serve!(port) do req
            received_method[] = req.method
            HTTP.Response(200, "")
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            @test delete_subscription(client, "sub-x") === nothing
            @test received_method[] == "DELETE"
        finally
            close(server)
        end
    end

    @testset "list_subscriptions (mock)" begin
        port = free_port()
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(Dict(
                "subscriptions" => [
                    Dict("name" => "projects/p/subscriptions/s1", "topic" => "projects/p/topics/t1"),
                    Dict("name" => "projects/p/subscriptions/s2", "topic" => "projects/p/topics/t2"),
                ],
            )))
        end
        try
            client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
            subs = collect(list_subscriptions(client))
            @test length(subs) == 2
            @test subs[1].name == "projects/p/subscriptions/s1"
        finally
            close(server)
        end
    end

    # ── Authorization header injection (mock) ───────────────
    @testset "auth header injected when not emulator (mock)" begin
        port = free_port()
        received_headers = Ref{HTTP.Headers}()
        server = HTTP.serve!(port) do req
            received_headers[] = req.headers
            HTTP.Response(200, ["Content-Type" => "application/json"],
                          JSON.json(Dict("messageIds" => ["x"])))
        end
        try
            client = PubSubClient("p", MockPSCreds(), "http://127.0.0.1:$port", false)
            publish(client, "topic-z", "hi")
            @test any(h -> h[1] == "Authorization" && h[2] == "Bearer mock-ps-token",
                      received_headers[])
        finally
            close(server)
        end
    end

    # ── Emulator integration tests ──────────────────────────
    started_container = nothing
    if !haskey(ENV, "PUBSUB_EMULATOR_HOST")
        try
            HTTP.get("http://localhost:8085/"; readtimeout=2)
            ENV["PUBSUB_EMULATOR_HOST"] = "localhost:8085"
            @info "Detected running PubSub emulator on localhost:8085"
        catch
            container_name = "pubsub-emulator-test-$(rand(UInt32))"
            try
                @info "Starting PubSub Emulator..."
                run(`docker run -d --name $container_name -p 8085:8085 gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators gcloud beta emulators pubsub start --host-port=0.0.0.0:8085`)
                connected = false
                for _ in 1:10
                    try
                        HTTP.get("http://localhost:8085/"; readtimeout=2)
                        connected = true
                        break
                    catch
                        sleep(2)
                    end
                end
                if connected
                    ENV["PUBSUB_EMULATOR_HOST"] = "localhost:8085"
                    started_container = container_name
                else
                    @warn "PubSub Emulator failed to start. Skipping integration tests."
                end
            catch e
                @warn "Could not spin up PubSub Emulator ($e). Skipping integration tests."
            end
        end
    end

    if haskey(ENV, "PUBSUB_EMULATOR_HOST")
        @info "Using PubSub Emulator at $(ENV["PUBSUB_EMULATOR_HOST"])"
        client = PubSubClient(project="test-project")
        project = "test-project"

        try
            @testset "Topic CRUD (emulator)" begin
                topic_id = "test-topic-$(rand(1000:9999))"
                topic = create_topic(client, topic_id)
                @test exists(topic)
                @test occursin(topic_id, topic.name)
                @test topic.name == "projects/$project/topics/$topic_id"

                got = get_topic(client, topic_id)
                @test got.name == topic.name

                delete_topic(client, topic_id)
            end

            @testset "list_topics paginates (emulator)" begin
                ids = ["lt-topic-$(i)-$(rand(1000:9999))" for i in 1:3]
                for id in ids
                    create_topic(client, id)
                end
                seen = String[]
                for t in list_topics(client)
                    push!(seen, t.name)
                end
                for id in ids
                    @test any(n -> endswith(n, "/$(id)"), seen)
                end
                for id in ids
                    delete_topic(client, id)
                end
            end

            @testset "publish + pull + acknowledge round-trip (emulator)" begin
                topic_id = "rt-topic-$(rand(1000:9999))"
                sub_id   = "rt-sub-$(rand(1000:9999))"
                try
                    create_topic(client, topic_id)
                    create_subscription(client, sub_id, topic_id; ack_deadline_seconds=10)

                    mid = publish(client, topic_id, "hello-pubsub";
                                  attributes=Dict("k" => "v"))
                    @test !isempty(mid)

                    # The emulator can take a moment to deliver
                    msgs = PubSubMessage[]
                    for _ in 1:10
                        msgs = pull(client, sub_id; max_messages=10)
                        !isempty(msgs) && break
                        sleep(0.2)
                    end
                    @test !isempty(msgs)
                    @test String(msgs[1].data) == "hello-pubsub"
                    @test msgs[1].attributes["k"] == "v"
                    @test msgs[1].ack_id !== nothing

                    acknowledge(client, sub_id, msgs[1])
                finally
                    try; delete_subscription(client, sub_id); catch; end
                    try; delete_topic(client, topic_id);      catch; end
                end
            end

            @testset "publish batch (emulator)" begin
                topic_id = "batch-topic-$(rand(1000:9999))"
                sub_id   = "batch-sub-$(rand(1000:9999))"
                try
                    create_topic(client, topic_id)
                    create_subscription(client, sub_id, topic_id)

                    ids = publish(client, topic_id, [
                        PubSubMessage("m1"),
                        PubSubMessage("m2"),
                        PubSubMessage("m3"),
                    ])
                    @test length(ids) == 3

                    received = PubSubMessage[]
                    for _ in 1:10
                        batch = pull(client, sub_id; max_messages=10)
                        append!(received, batch)
                        length(received) >= 3 && break
                        sleep(0.2)
                    end
                    @test length(received) >= 3
                    payloads = sort([String(m.data) for m in received[1:3]])
                    @test payloads == ["m1", "m2", "m3"]
                    acknowledge(client, sub_id, [m.ack_id for m in received if m.ack_id !== nothing])
                finally
                    try; delete_subscription(client, sub_id); catch; end
                    try; delete_topic(client, topic_id);      catch; end
                end
            end

            @testset "list_subscriptions (emulator)" begin
                topic_id = "ls-topic-$(rand(1000:9999))"
                sub_ids  = ["ls-sub-$(i)-$(rand(1000:9999))" for i in 1:2]
                try
                    create_topic(client, topic_id)
                    for s in sub_ids
                        create_subscription(client, s, topic_id)
                    end
                    seen = [sub.name for sub in list_subscriptions(client)]
                    for s in sub_ids
                        @test any(n -> endswith(n, "/$(s)"), seen)
                    end
                finally
                    for s in sub_ids
                        try; delete_subscription(client, s); catch; end
                    end
                    try; delete_topic(client, topic_id); catch; end
                end
            end
        finally
            if started_container !== nothing
                try
                    run(`docker stop $started_container`)
                    run(`docker rm $started_container`)
                catch
                end
            end
        end
    end
end
