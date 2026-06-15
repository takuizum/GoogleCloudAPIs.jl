using Test
using Aqua
using GoogleApiCore
using HTTP
using JSON
import Logging
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
# `headers` でレスポンスごとの追加ヘッダ（例: Retry-After）を指定できる。
# `request_count` で実際に届いたリクエスト数を観測できる。
function with_mock_server(f, statuses::Vector{Int},
                          bodies::Vector{String}=fill("{}", length(statuses));
                          headers::Union{Nothing, Vector{<:Vector}}=nothing,
                          request_count::Union{Nothing, Ref{Int}}=nothing)
    port = free_port()
    idx  = Ref(0)
    server = HTTP.serve!(port) do req
        idx[] += 1
        request_count !== nothing && (request_count[] = idx[])
        i = min(idx[], length(statuses))
        h = ["Content-Type" => "application/json"]
        headers !== nothing && append!(h, headers[i])
        HTTP.Response(statuses[i], h, bodies[i])
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
        # idempotent 指定で POST もリトライ対象になる
        @test  sr("POST", 500; idempotent=true)
        @test  sr("POST", 429; idempotent=true)
        @test !sr("POST", 400; idempotent=true)   # 4xx(≠429) は常に raise
        @test !sr("POST", 200; idempotent=true)
    end

    # ── _retry_delay ────────────────────────────────────────
    @testset "_retry_delay" begin
        rd  = GoogleApiCore._retry_delay
        cfg = RetryConfig(initial_delay=1.0, multiplier=2.0, max_delay=10.0)

        # ジッターは +10% までなので [base, base*1.1] に収まる
        @test 1.0 <= rd(cfg, 1, nothing) <= 1.1
        @test 2.0 <= rd(cfg, 2, nothing) <= 2.2
        @test 10.0 <= rd(cfg, 10, nothing) <= 11.0   # max_delay でキャップ

        # 整数 Retry-After はバックオフより優先される
        @test 3.0 <= rd(cfg, 1, "3") <= 3.3
        @test 0.0 <= rd(cfg, 5, "0") <= 0.001        # 0 は即時
        @test 10.0 <= rd(cfg, 1, "9999") <= 11.0     # max_delay でキャップ
        @test 3.0 <= rd(cfg, 1, " 3 ") <= 3.3        # 空白は許容

        # パースできない値はバックオフへフォールバック
        @test 2.0 <= rd(cfg, 2, "Wed, 21 Oct 2026 07:28:00 GMT") <= 2.2
        @test 2.0 <= rd(cfg, 2, "-5") <= 2.2          # 負値は無視
        @test 2.0 <= rd(cfg, 2, "abc") <= 2.2
    end

    # ── do_request_with_retry ────────────────────────────────
    @testset "do_request_with_retry: 200 OK" begin
        with_mock_server([200], ["""{"ok":true}"""]) do url
            cfg  = RetryConfig(initial_delay=0.0, max_attempts=3)
            resp = do_request_with_retry("GET", url, [], ""; config=cfg)
            @test resp.status == 200
            @test JSON.parse(IOBuffer(resp.body))["ok"] == true
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
        count = Ref(0)
        with_mock_server([500, 200]; request_count=count) do url
            cfg = RetryConfig(initial_delay=0.0, max_attempts=5)
            @test_throws Exception do_request_with_retry("POST", url, [], "{}"; config=cfg)
        end
        @test count[] == 1   # リトライせず 1 リクエストで失敗
    end

    @testset "do_request_with_retry: idempotent POST retries on 500" begin
        count = Ref(0)
        with_mock_server([500, 200], ["{}", """{"done":true}"""];
                         request_count=count) do url
            cfg  = RetryConfig(initial_delay=0.0, max_attempts=5)
            resp = do_request_with_retry("POST", url, [], "{}";
                                         config=cfg, idempotent=true)
            @test resp.status == 200
        end
        @test count[] == 2
    end

    @testset "do_request_with_retry: Retry-After overrides backoff" begin
        # initial_delay=5.0 のままだと 1 回のリトライに 5 秒以上かかるが、
        # Retry-After: 0 が優先されれば 1 秒未満で完了する。
        with_mock_server([429, 200], ["{}", """{"done":true}"""];
                         headers=[["Retry-After" => "0"], Pair{String,String}[]]) do url
            cfg = RetryConfig(initial_delay=5.0, max_attempts=3)
            t = @elapsed resp = do_request_with_retry("GET", url, [], ""; config=cfg)
            @test resp.status == 200
            @test t < 1.0
        end
    end

    @testset "do_request_with_retry: retry log is debug-level" begin
        with_mock_server([500, 200]) do url
            cfg = RetryConfig(initial_delay=0.0, max_attempts=3)
            # デフォルトの info レベルではリトライログは出ない
            @test_logs min_level=Logging.Info do_request_with_retry("GET", url, [], ""; config=cfg)
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

    # ── resolve_endpoint ─────────────────────────────────────
    @testset "resolve_endpoint" begin
        re = GoogleApiCore.resolve_endpoint
        # explicit wins; http:// => emulator, https:// => production
        @test re(; explicit="http://127.0.0.1:9050", production="https://x") ==
              ("http://127.0.0.1:9050", true)
        @test re(; explicit="https://custom.example", production="https://x") ==
              ("https://custom.example", false)
        # emulator_host env style: scheme added when missing, marked emulator
        @test re(; emulator_host="localhost:8085", production="https://x") ==
              ("http://localhost:8085", true)
        @test re(; emulator_host="http://localhost:4443", production="https://x") ==
              ("http://localhost:4443", true)
        # fallback to production
        @test re(; production="https://storage.googleapis.com") ==
              ("https://storage.googleapis.com", false)
        # explicit takes precedence over emulator_host
        @test re(; emulator_host="localhost:1", explicit="https://p", production="https://x") ==
              ("https://p", false)
    end

    # ── service_request ──────────────────────────────────────
    @testset "service_request: builds URL, query, content-type, sign!" begin
        seen = Ref{Tuple{String,HTTP.Headers}}()
        port = free_port()
        server = HTTP.serve!(port) do req
            seen[] = (req.target, req.headers)
            HTTP.Response(200, ["Content-Type" => "application/json"], """{"ok":true}""")
        end
        try
            signer = req -> push!(req.headers, "Authorization" => "Bearer T")
            resp = service_request("GET", "http://127.0.0.1:$port", "v1/things";
                query=Dict("a" => "1", "b" => "x y"),
                content_type="application/json", sign! = signer)
            @test resp.status == 200
            target, hdrs = seen[]
            @test startswith(target, "/v1/things?")
            @test occursin("a=1", target)
            @test occursin("b=x%20y", target) || occursin("b=x+y", target)  # space-encoded
            @test any(h -> h[1] == "Content-Type" && h[2] == "application/json", hdrs)
            @test any(h -> h[1] == "Authorization" && h[2] == "Bearer T", hdrs)
        finally
            close(server)
        end
    end

    @testset "service_request: nothing signer sends unsigned, idempotent retries" begin
        hits = Ref(0)
        port = free_port()
        server = HTTP.serve!(port) do req
            hits[] += 1
            HTTP.Response(hits[] == 1 ? 503 : 200, "{}")
        end
        try
            cfg = RetryConfig(initial_delay=0.0, max_attempts=3)
            resp = service_request("POST", "http://127.0.0.1:$port", "p";
                body="{}", content_type="application/json",
                sign! = nothing, idempotent=true, config=cfg)
            @test resp.status == 200
            @test hits[] == 2
        finally
            close(server)
        end
    end

    @testset "do_request_with_retry: response_stream reset on retry (no accumulation)" begin
        # First attempt 503s (writes an error body to the stream); a seekable
        # stream must be rewound so the retried success body is the only content.
        hits = Ref(0)
        port = free_port()
        server = HTTP.serve!(port) do _req
            hits[] += 1
            hits[] == 1 ? HTTP.Response(503, "transient error body") :
                          HTTP.Response(200, "OK BODY")
        end
        try
            cfg = RetryConfig(initial_delay=0.0, max_attempts=3)
            buf = IOBuffer()
            resp = do_request_with_retry("GET", "http://127.0.0.1:$port/", [], "";
                                         config=cfg, response_stream=buf)
            @test resp.status == 200
            @test hits[] == 2
            @test String(take!(buf)) == "OK BODY"   # error body did not accumulate
        finally
            close(server)
        end
    end

    @testset "do_request_with_retry: IO body streams and is not retried" begin
        hits = Ref(0)
        bodies = String[]
        port = free_port()
        server = HTTP.serve!(port) do req
            hits[] += 1
            push!(bodies, String(req.body))
            HTTP.Response(200, "{}")
        end
        try
            cfg = RetryConfig(initial_delay=0.0, max_attempts=3)
            io = IOBuffer(Vector{UInt8}("streamed-upload"))
            resp = do_request_with_retry("POST", "http://127.0.0.1:$port/", [], io;
                                         config=cfg, idempotent=true)
            @test resp.status == 200
            @test hits[] == 1
            @test bodies[1] == "streamed-upload"
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
