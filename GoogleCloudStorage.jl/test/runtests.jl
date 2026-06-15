using Test
using GoogleCloudStorage
using HTTP
using JSON
using Aqua
import Sockets
import GoogleAuth
import GoogleAuth: get_token  # extend for stub creds

# ────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────
function free_port()
    srv = Sockets.listen(Sockets.localhost, 0)
    port = Sockets.getsockname(srv)[2]
    close(srv)
    return port
end

# Stub credentials for auth-header tests
struct MockGCSCreds <: GoogleAuth.Credentials end
get_token(::MockGCSCreds) = GoogleAuth.Token("mock-gcs-token", 3600, "Bearer")

# Helper: build a GCS bucket JSON object
function bucket_json(; name="my-bucket", location="US", storage_class="STANDARD")
    JSON.json(Dict("name" => name, "location" => location, "storageClass" => storage_class))
end

# Helper: build a GCS object metadata JSON
function object_json(; bucket="my-bucket", name="file.txt",
                       size="42", content_type="text/plain", generation="1")
    JSON.json(Dict(
        "bucket" => bucket,
        "name" => name,
        "size" => size,
        "contentType" => content_type,
        "generation" => generation,
    ))
end

# ────────────────────────────────────────────────────────────
@testset "GoogleCloudStorage.jl" begin

    @testset "Aqua" begin
        Aqua.test_all(GoogleCloudStorage; ambiguities=false, persistent_tasks=false)
    end

    # ── get_bucket via mock server ───────────────────────────
    @testset "get_bucket (mock server)" begin
        port = free_port()
        body = bucket_json(; name="alpha", location="EU", storage_class="NEARLINE")
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            b = get_bucket(client, "alpha")
            @test b.name          == "alpha"
            @test b.location      == "EU"
            @test b.storage_class == "NEARLINE"
        finally
            close(server)
        end
    end

    # ── list_buckets via mock server (single page) ───────────
    @testset "list_buckets single page (mock server)" begin
        port = free_port()
        body = JSON.json(Dict(
            "kind"  => "storage#buckets",
            "items" => [
                Dict("name" => "bucket-a", "location" => "US",   "storageClass" => "STANDARD"),
                Dict("name" => "bucket-b", "location" => "ASIA", "storageClass" => "COLDLINE"),
            ],
        ))
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            buckets = collect(list_buckets(client))
            @test length(buckets) == 2
            @test buckets[1].name == "bucket-a"
            @test buckets[2].name == "bucket-b"
            @test buckets[2].storage_class == "COLDLINE"
        finally
            close(server)
        end
    end

    # ── get_object metadata via mock server ──────────────────
    @testset "get_object metadata (mock server)" begin
        port = free_port()
        body = object_json(; bucket="bkt", name="data/file.csv", size="1024",
                             content_type="text/csv", generation="7")
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            obj = get_object(client, "bkt", "data/file.csv")
            @test obj.bucket       == "bkt"
            @test obj.name         == "data/file.csv"
            @test obj.size         == 1024
            @test obj.content_type == "text/csv"
            @test obj.generation   == 7
        finally
            close(server)
        end
    end

    # ── download_object via mock server ──────────────────────
    @testset "download_object returns bytes (mock server)" begin
        content = Vector{UInt8}("binary payload")
        port = free_port()
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/octet-stream"], content)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            got = download_object(client, "bkt", "obj.bin")
            @test got == content
        finally
            close(server)
        end
    end

    @testset "download_object IO variant (mock server)" begin
        content = Vector{UInt8}("io payload")
        port = free_port()
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/octet-stream"], content)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            buf = IOBuffer()
            ret = download_object(client, "bkt", "obj.bin", buf)
            @test ret === nothing
            @test take!(buf) == content
        finally
            close(server)
        end
    end

    @testset "download_object streams large payload into IO (mock server)" begin
        # ~256 KiB to exercise the streaming (response_stream) path beyond a
        # single buffer; the bytes must arrive intact and in order.
        content = rand(UInt8, 256 * 1024)
        port = free_port()
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/octet-stream"], content)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            buf = IOBuffer()
            download_object(client, "bkt", "big.bin", buf)
            @test take!(buf) == content
        finally
            close(server)
        end
    end

    # ── upload_object via mock server (three data forms) ─────
    @testset "upload_object with Vector{UInt8} (mock server)" begin
        port = free_port()
        meta = object_json(; bucket="bkt", name="up.bin", size="5")
        received_body = Ref{Vector{UInt8}}()
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            HTTP.Response(200, ["Content-Type" => "application/json"], meta)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            data = UInt8[1, 2, 3, 4, 5]
            obj = upload_object(client, "bkt", "up.bin", data)
            @test obj.name   == "up.bin"
            @test obj.bucket == "bkt"
            @test received_body[] == data
        finally
            close(server)
        end
    end

    @testset "upload_object with String (mock server)" begin
        port = free_port()
        meta = object_json(; bucket="bkt", name="hello.txt", size="13",
                             content_type="text/plain")
        received_body = Ref{Vector{UInt8}}()
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            HTTP.Response(200, ["Content-Type" => "application/json"], meta)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            obj = upload_object(client, "bkt", "hello.txt", "hello, world!";
                                content_type="text/plain")
            @test obj.name         == "hello.txt"
            @test obj.content_type == "text/plain"
            @test received_body[] == Vector{UInt8}("hello, world!")
        finally
            close(server)
        end
    end

    @testset "upload_object with IO (mock server)" begin
        port = free_port()
        meta = object_json(; bucket="bkt", name="io.bin", size="4")
        received_body = Ref{Vector{UInt8}}()
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            HTTP.Response(200, ["Content-Type" => "application/json"], meta)
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            src = IOBuffer(UInt8[0xDE, 0xAD, 0xBE, 0xEF])
            obj = upload_object(client, "bkt", "io.bin", src)
            @test obj.name == "io.bin"
            @test received_body[] == UInt8[0xDE, 0xAD, 0xBE, 0xEF]
        finally
            close(server)
        end
    end

    # ── create_bucket via mock server ────────────────────────
    @testset "create_bucket (mock server)" begin
        port = free_port()
        received_method = Ref{String}()
        received_body   = Ref{Vector{UInt8}}()
        received_query  = Ref{String}()
        body = bucket_json(; name="new-bkt", location="ASIA", storage_class="STANDARD")
        server = HTTP.serve!(port) do req
            received_method[] = req.method
            received_body[]   = req.body
            received_query[]  = req.target
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = GoogleCloudStorage.Client("my-proj", nothing, "http://127.0.0.1:$port", true)
            b = create_bucket(client, "new-bkt"; location="ASIA", storage_class="STANDARD")
            @test b.name          == "new-bkt"
            @test b.location      == "ASIA"
            @test b.storage_class == "STANDARD"
            @test received_method[] == "POST"
            @test occursin("project=my-proj", received_query[])
            doc = JSON.parse(IOBuffer(received_body[]))
            @test String(doc["name"])         == "new-bkt"
            @test String(doc["location"])     == "ASIA"
            @test String(doc["storageClass"]) == "STANDARD"
        finally
            close(server)
        end
    end

    # ── delete_bucket via mock server ────────────────────────
    @testset "delete_bucket (mock server)" begin
        port = free_port()
        received_method = Ref{String}()
        received_path   = Ref{String}()
        server = HTTP.serve!(port) do req
            received_method[] = req.method
            received_path[]   = req.target
            HTTP.Response(204, "")
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            ret = delete_bucket(client, "doomed-bkt")
            @test ret === nothing
            @test received_method[] == "DELETE"
            @test occursin("/storage/v1/b/doomed-bkt", received_path[])
        finally
            close(server)
        end
    end

    # ── delete_object via mock server ────────────────────────
    @testset "delete_object (mock server)" begin
        port = free_port()
        received_method = Ref{String}()
        received_path   = Ref{String}()
        server = HTTP.serve!(port) do req
            received_method[] = req.method
            received_path[]   = req.target
            HTTP.Response(204, "")
        end
        try
            client = GoogleCloudStorage.Client("proj", nothing, "http://127.0.0.1:$port", true)
            ret = delete_object(client, "bkt", "path/to/file.txt")
            @test ret === nothing
            @test received_method[] == "DELETE"
            @test occursin("/storage/v1/b/bkt/o/path%2Fto%2Ffile.txt", received_path[])
        finally
            close(server)
        end
    end

    # ── Authorization header injected for non-emulator ───────
    @testset "Client injects Authorization header (mock server)" begin
        received_headers = Ref{HTTP.Headers}()
        port = free_port()
        body = bucket_json()
        server = HTTP.serve!(port) do req
            received_headers[] = req.headers
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            # is_emulator=false → auth header should be present
            client = GoogleCloudStorage.Client("proj", MockGCSCreds(),
                                               "http://127.0.0.1:$port", false)
            get_bucket(client, "my-bucket")
            @test any(h -> h[1] == "Authorization" && h[2] == "Bearer mock-gcs-token",
                      received_headers[])
        finally
            close(server)
        end
    end

    # ── ADC loading (mock credentials file) ──────────────────
    include("adc_test.jl")

    # ── Emulator integration tests ───────────────────────────
    started_container = nothing
    if !haskey(ENV, "STORAGE_EMULATOR_HOST")
        try
            HTTP.get("http://localhost:4443/storage/v1/b?project=test-project"; readtimeout=2)
            ENV["STORAGE_EMULATOR_HOST"] = "http://localhost:4443"
            @info "Detected running fake-gcs-server on localhost:4443"
        catch
            container_name = "gcs-emulator-test-$(rand(UInt32))"
            try
                @info "Starting fake-gcs-server..."
                run(`docker run -d --name $container_name -p 4443:4443 fsouza/fake-gcs-server:1.47.7 -scheme http`)
                connected = false
                for _ in 1:15
                    try
                        HTTP.get("http://localhost:4443/storage/v1/b?project=test-project"; readtimeout=2)
                        connected = true
                        break
                    catch
                        sleep(2)
                    end
                end
                if connected
                    ENV["STORAGE_EMULATOR_HOST"] = "http://localhost:4443"
                    started_container = container_name
                else
                    @warn "fake-gcs-server failed to start. Skipping integration tests."
                end
            catch e
                @warn "Could not spin up fake-gcs-server ($e). Skipping integration tests."
            end
        end
    end

    if haskey(ENV, "STORAGE_EMULATOR_HOST")
        @info "Using GCS emulator at $(ENV["STORAGE_EMULATOR_HOST"])"
        client = Client("test-project")
        bucket_name = "gcs-test-bucket-$(rand(1000:9999))"
        try
            HTTP.post(
                "$(ENV["STORAGE_EMULATOR_HOST"])/storage/v1/b?project=test-project",
                ["Content-Type" => "application/json"],
                JSON.json(Dict("name" => bucket_name)),
            )

            @testset "list_buckets contains created bucket (emulator)" begin
                names = [b.name for b in list_buckets(client)]
                @test bucket_name in names
            end

            @testset "get_bucket (emulator)" begin
                b = get_bucket(client, bucket_name)
                @test b.name == bucket_name
            end

            @testset "upload + download round-trip (emulator)" begin
                payload = Vector{UInt8}("hello, world")
                obj = upload_object(client, bucket_name, "greet.txt", payload;
                                    content_type="text/plain")
                @test obj.name == "greet.txt"
                got = download_object(client, bucket_name, "greet.txt")
                @test got == payload

                io = IOBuffer()
                download_object(client, bucket_name, "greet.txt", io)
                @test take!(io) == payload
            end

            @testset "get_object metadata (emulator)" begin
                upload_object(client, bucket_name, "meta.txt", "content")
                obj = get_object(client, bucket_name, "meta.txt")
                @test obj.name   == "meta.txt"
                @test obj.bucket == bucket_name
                @test obj.size   == length("content")
            end

            @testset "list_objects with prefix (emulator)" begin
                upload_object(client, bucket_name, "logs/a.txt", "a")
                upload_object(client, bucket_name, "logs/b.txt", "b")
                upload_object(client, bucket_name, "other.txt",  "c")
                seen = [o.name for o in list_objects(client, bucket_name; prefix="logs/")]
                @test "logs/a.txt" in seen
                @test "logs/b.txt" in seen
                @test !("other.txt" in seen)
            end

            @testset "delete_object lifecycle (emulator)" begin
                upload_object(client, bucket_name, "to-delete.txt", "bye")
                @test get_object(client, bucket_name, "to-delete.txt").name == "to-delete.txt"
                delete_object(client, bucket_name, "to-delete.txt")
                # After deletion, get_object should raise
                @test_throws Exception get_object(client, bucket_name, "to-delete.txt")
            end

            @testset "create_bucket + delete_bucket lifecycle (emulator)" begin
                new_bkt = "lifecycle-bucket-$(rand(1000:9999))"
                b = create_bucket(client, new_bkt; location="US")
                @test b.name == new_bkt
                # Bucket should now appear in list
                names = [bk.name for bk in list_buckets(client)]
                @test new_bkt in names
                # Cleanup
                delete_bucket(client, new_bkt)
                names2 = [bk.name for bk in list_buckets(client)]
                @test !(new_bkt in names2)
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
