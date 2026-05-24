using Test
using Aqua
using GoogleApiCore
using HTTP
using JSON
import Sockets
import GoogleApiCore: get_items, get_next_token  # メソッドを追加するためにimportする

# ────────────────────────────────────────────────────────────
# ヘルパー
# ────────────────────────────────────────────────────────────
function free_port()
    srv = Sockets.listen(Sockets.localhost, 0)
    port = Sockets.getsockname(srv)[2]
    close(srv)
    return port
end

# do ブロックを最初の引数として受け取る（Julia の do 記法に合わせる）
function with_mock_server(f, statuses::Vector{Int},
                          bodies::Vector{String}=fill("{}", length(statuses)))
    port = free_port()
    idx  = Ref(0)
    server = HTTP.serve!(port) do req
        idx[] += 1
        i = min(idx[], length(statuses))
        HTTP.Response(statuses[i], ["Content-Type" => "application/json"], bodies[i])
    end
    try
        f("http://127.0.0.1:$port")
    finally
        close(server)
    end
end

# ────────────────────────────────────────────────────────────
# PagedIterator 用のテスト型をトップレベルで定義
# ────────────────────────────────────────────────────────────
struct OnePage <: AbstractPage
    items::Vector{Int}
end
get_items(p::OnePage)      = p.items
get_next_token(p::OnePage) = nothing

struct MultiPage <: AbstractPage
    items::Vector{String}
    token::Union{String,Nothing}
end
get_items(p::MultiPage)      = p.items
get_next_token(p::MultiPage) = p.token

struct EmptyPage <: AbstractPage end
get_items(::EmptyPage)      = Int[]
get_next_token(::EmptyPage) = nothing

struct SzPage <: AbstractPage
    items::Vector{Int}
end
get_items(p::SzPage)     = p.items
get_next_token(::SzPage) = nothing

# ────────────────────────────────────────────────────────────
@testset "GoogleApiCore.jl" begin

    @testset "Aqua" begin
        Aqua.test_all(GoogleApiCore; ambiguities=false, persistent_tasks=false)
    end

    # ── RetryConfig ─────────────────────────────────────────
    @testset "RetryConfig defaults" begin
        cfg = RetryConfig()
        @test cfg.initial_delay == 1.0
        @test cfg.multiplier    == 2.0
        @test cfg.max_delay     == 60.0
        @test cfg.max_attempts  == 5
    end

    @testset "RetryConfig custom" begin
        cfg = RetryConfig(initial_delay=0.5, max_attempts=3)
        @test cfg.initial_delay == 0.5
        @test cfg.max_attempts  == 3
    end

    # ── should_retry ────────────────────────────────────────
    @testset "should_retry" begin
        sr = GoogleApiCore.should_retry
        @test  sr("GET", 500)
        @test  sr("GET", 503)
        @test  sr("GET", 429)
        @test  sr("PUT", 500)
        @test  sr("PUT", 429)
        @test !sr("POST", 500)   # POST はリトライしない
        @test !sr("POST", 429)
        @test !sr("GET", 200)
        @test !sr("GET", 404)
        @test !sr("GET", 400)
    end

    # ── do_request_with_retry ────────────────────────────────
    @testset "do_request_with_retry: 200 OK" begin
        with_mock_server([200], ["""{"ok":true}"""]) do url
            cfg  = RetryConfig(initial_delay=0.0, max_attempts=3)
            resp = do_request_with_retry("GET", url, [], ""; config=cfg)
            @test resp.status == 200
            @test JSON.parse(String(resp.body))["ok"] == true
        end
    end

    @testset "do_request_with_retry: GET retries on 500 then 200" begin
        with_mock_server([500, 500, 200], ["{}", "{}", """{"done":true}"""]) do url
            cfg  = RetryConfig(initial_delay=0.0, max_attempts=5)
            resp = do_request_with_retry("GET", url, [], ""; config=cfg)
            @test resp.status == 200
        end
    end

    @testset "do_request_with_retry: POST does not retry on 500" begin
        with_mock_server([500, 200]) do url
            cfg = RetryConfig(initial_delay=0.0, max_attempts=5)
            @test_throws Exception do_request_with_retry("POST", url, [], "{}"; config=cfg)
        end
    end

    @testset "do_request_with_retry: exhausts max_attempts" begin
        with_mock_server([500, 500, 500, 500, 500]) do url
            cfg = RetryConfig(initial_delay=0.0, max_attempts=3)
            @test_throws Exception do_request_with_retry("GET", url, [], ""; config=cfg)
        end
    end

    @testset "do_request_with_retry: passes request headers" begin
        received = Ref{HTTP.Headers}()
        port   = free_port()
        server = HTTP.serve!(port) do req
            received[] = req.headers
            HTTP.Response(200, "")
        end
        try
            cfg = RetryConfig(initial_delay=0.0, max_attempts=1)
            do_request_with_retry("GET", "http://127.0.0.1:$port/",
                                  ["X-Test" => "hello"], ""; config=cfg)
            @test any(h -> h[1] == "X-Test" && h[2] == "hello", received[])
        finally
            close(server)
        end
    end

    # ── PagedIterator ────────────────────────────────────────
    @testset "PagedIterator: single page" begin
        iter = PagedIterator(_ -> OnePage([10, 20, 30]))
        @test collect(iter) == [10, 20, 30]
    end

    @testset "PagedIterator: multiple pages" begin
        pages = [
            MultiPage(["a","b"], "p2"),
            MultiPage(["c","d"], "p3"),
            MultiPage(["e"],     nothing),
        ]
        call = Ref(0)
        iter = PagedIterator() do _token
            call[] += 1
            pages[call[]]
        end
        @test collect(iter) == ["a","b","c","d","e"]
        @test call[] == 3
    end

    @testset "PagedIterator: empty first page" begin
        iter = PagedIterator(_ -> EmptyPage())
        @test collect(iter) == []
    end

    @testset "PagedIterator: SizeUnknown" begin
        iter = PagedIterator(_ -> SzPage([1,2]))
        @test Base.IteratorSize(typeof(iter)) == Base.SizeUnknown()
    end

    # ── LROperation ─────────────────────────────────────────
    @testset "LROperation" begin
        op = LROperation("projects/p/operations/op1", false)
        @test op.name == "projects/p/operations/op1"
        @test !op.done
        @test op._task === nothing
    end
end
