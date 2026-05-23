using Test
using Aqua
using GoogleAuth
using JSON3
using HTTP
using URIs
import SHA
import Sockets

# ────────────────────────────────────────────────────────────
# テスト用スタブ: HTTP を一切使わず固定 Token を返す Credentials
# ────────────────────────────────────────────────────────────
struct StubCredentials <: Credentials end
GoogleAuth.get_token(::StubCredentials) = Token("stub-access-token", 3600, "Bearer")

@testset "GoogleAuth.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(GoogleAuth; ambiguities=false)
    end

    # ── 型の構造 ─────────────────────────────────────────────
    @testset "Token struct" begin
        t = Token("my-token", 3599, "Bearer")
        @test t.access_token == "my-token"
        @test t.expires_in   == 3599
        @test t.token_type   == "Bearer"
    end

    @testset "Credentials subtypes" begin
        sa = ServiceAccountCredentials("proj", "sa@p.iam", "key-id", "private-key", "https://oauth2.googleapis.com/token")
        @test sa isa Credentials
        @test sa.project_id   == "proj"
        @test sa.client_email == "sa@p.iam"

        uc = UserCredentials("client-id", "client-secret", "refresh-token", "authorized_user")
        @test uc isa Credentials
        @test uc.refresh_token == "refresh-token"

        cc = ComputeCredentials()
        @test cc isa Credentials
    end

    # ── authorization_header ─────────────────────────────────
    @testset "authorization_header format" begin
        h = authorization_header(StubCredentials())
        @test h isa Pair{String, String}
        @test h.first  == "Authorization"
        @test h.second == "Bearer stub-access-token"
    end

    @testset "authorization_header uses get_token result" begin
        struct TokenCreds <: Credentials end
        GoogleAuth.get_token(::TokenCreds) = Token("xyz-999", 3600, "Bearer")
        h = authorization_header(TokenCreds())
        @test h.second == "Bearer xyz-999"
    end

    # ── load_credentials_from_file ───────────────────────────
    @testset "load_credentials_from_file: service_account JSON" begin
        json = """
        {
          "type": "service_account",
          "project_id": "my-project",
          "client_email": "sa@my-project.iam.gserviceaccount.com",
          "private_key_id": "key123",
          "private_key": "-----BEGIN RSA PRIVATE KEY-----\\nMIIEowIBAAKCAQ==\\n-----END RSA PRIVATE KEY-----\\n",
          "token_uri": "https://oauth2.googleapis.com/token"
        }
        """
        path = tempname() * ".json"
        write(path, json)
        creds = GoogleAuth.load_credentials_from_file(path)
        rm(path)

        @test creds isa ServiceAccountCredentials
        @test creds.project_id   == "my-project"
        @test creds.client_email == "sa@my-project.iam.gserviceaccount.com"
        @test creds.private_key_id == "key123"
        @test creds.token_uri == "https://oauth2.googleapis.com/token"
    end

    @testset "load_credentials_from_file: authorized_user JSON" begin
        json = """
        {
          "type": "authorized_user",
          "client_id": "cid.apps.googleusercontent.com",
          "client_secret": "csec",
          "refresh_token": "rtoken"
        }
        """
        path = tempname() * ".json"
        write(path, json)
        creds = GoogleAuth.load_credentials_from_file(path)
        rm(path)

        @test creds isa UserCredentials
        @test creds.client_id     == "cid.apps.googleusercontent.com"
        @test creds.refresh_token == "rtoken"
    end

    @testset "load_credentials_from_file: file not found" begin
        @test_throws Exception GoogleAuth.load_credentials_from_file("/nonexistent/path.json")
    end

    @testset "load_credentials_from_file: unknown type" begin
        json = """{"type": "unknown_type"}"""
        path = tempname() * ".json"
        write(path, json)
        @test_throws Exception GoogleAuth.load_credentials_from_file(path)
        rm(path)
    end

    # ── get_application_default via GOOGLE_APPLICATION_CREDENTIALS ──
    @testset "get_application_default via env var" begin
        json = """
        {
          "type": "authorized_user",
          "client_id": "adc-cid",
          "client_secret": "adc-csec",
          "refresh_token": "adc-rtoken"
        }
        """
        path = tempname() * ".json"
        write(path, json)

        old = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", nothing)
        ENV["GOOGLE_APPLICATION_CREDENTIALS"] = path
        try
            creds = get_application_default()
            @test creds isa CachedCredentials
            @test creds.inner isa UserCredentials
            @test creds.inner.client_id == "adc-cid"
        finally
            if old === nothing
                delete!(ENV, "GOOGLE_APPLICATION_CREDENTIALS")
            else
                ENV["GOOGLE_APPLICATION_CREDENTIALS"] = old
            end
            rm(path)
        end
    end

    # ── ComputeCredentials: メタサーバ不在時は例外 ──────────────
    @testset "get_token(ComputeCredentials) throws outside GCP" begin
        @test_throws Exception get_token(ComputeCredentials())
    end

    # ── CachedCredentials ────────────────────────────────────
    @testset "CachedCredentials wraps and caches" begin
        call_count = Ref(0)
        struct CountingCreds <: Credentials end
        GoogleAuth.get_token(::CountingCreds) = begin
            call_count[] += 1
            Token("counted-token", 3600, "Bearer")
        end

        cached = CachedCredentials(CountingCreds())
        @test cached isa CachedCredentials
        @test cached._token === nothing

        t1 = get_token(cached)
        @test call_count[] == 1
        @test t1.access_token == "counted-token"

        # Second call should use cache — no new fetch
        t2 = get_token(cached)
        @test call_count[] == 1
        @test t2.access_token == "counted-token"

        # authorization_header also uses the cache
        h = authorization_header(cached)
        @test call_count[] == 1
        @test h == ("Authorization" => "Bearer counted-token")
    end

    @testset "CachedCredentials refreshes near expiry" begin
        mutable struct ShortLivedCreds <: Credentials
            n::Int
        end
        GoogleAuth.get_token(c::ShortLivedCreds) = begin
            c.n += 1
            # expires_in = 200 s  →  300 s buffer > 200 s  →  always "expired"
            Token("token-$(c.n)", 200, "Bearer")
        end

        inner = ShortLivedCreds(0)
        cached = CachedCredentials(inner)

        t1 = get_token(cached)
        @test inner.n == 1
        t2 = get_token(cached)   # 200 < 300 buffer → should refresh
        @test inner.n == 2
        @test t2.access_token == "token-2"
    end

    # ── OAuth: PKCE ──────────────────────────────────────────
    @testset "PKCE _pkce_pair defaults" begin
        v, c = GoogleAuth._pkce_pair()
        @test length(v) == 64
        @test all(in(GoogleAuth._PKCE_ALPHABET), v)
        # challenge = base64url(SHA256(verifier))
        @test c == GoogleAuth._base64url(SHA.sha256(codeunits(v)))
        # No padding characters
        @test !occursin('=', c)
        @test !occursin('+', c)
        @test !occursin('/', c)
    end

    @testset "PKCE custom and invalid lengths" begin
        v43, _ = GoogleAuth._pkce_pair(43)
        v128, _ = GoogleAuth._pkce_pair(128)
        @test length(v43) == 43
        @test length(v128) == 128
        @test_throws ArgumentError GoogleAuth._pkce_pair(42)
        @test_throws ArgumentError GoogleAuth._pkce_pair(129)
    end

    @testset "_base64url RFC 4648 §5" begin
        # SHA256 of empty string in url-safe base64 without padding
        h = GoogleAuth._base64url(SHA.sha256(UInt8[]))
        @test h == "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"
    end

    @testset "_random_state randomness and shape" begin
        s1 = GoogleAuth._random_state()
        s2 = GoogleAuth._random_state()
        @test s1 != s2
        @test !occursin('=', s1)
        @test length(s1) > 10
    end

    # ── OAuth: URL builder ──────────────────────────────────
    @testset "_build_auth_url has all required params" begin
        url = GoogleAuth._build_auth_url(;
            client_id="cid",
            redirect_uri="http://127.0.0.1:1234/",
            scopes=["scope1", "scope2"],
            state="STATE",
            code_challenge="CHALLENGE",
        )
        @test startswith(url, "https://accounts.google.com/o/oauth2/v2/auth?")
        parsed = URIs.URI(url)
        params = Dict(URIs.queryparampairs(parsed))
        @test params["client_id"]             == "cid"
        @test params["response_type"]         == "code"
        @test params["redirect_uri"]          == "http://127.0.0.1:1234/"
        @test params["scope"]                 == "scope1 scope2"
        @test params["state"]                 == "STATE"
        @test params["code_challenge"]        == "CHALLENGE"
        @test params["code_challenge_method"] == "S256"
        @test params["access_type"]           == "offline"
        @test params["prompt"]                == "consent"
    end

    # ── OAuth: callback server ───────────────────────────────
    @testset "_wait_for_callback success path" begin
        port = GoogleAuth._free_port()
        task = @async GoogleAuth._wait_for_callback(port, "S123", 10)
        sleep(0.3)  # let the server bind
        resp = HTTP.get("http://127.0.0.1:$port/?code=AUTH_CODE&state=S123")
        @test resp.status == 200
        @test occursin("Authentication complete", String(resp.body))
        @test fetch(task) == "AUTH_CODE"
    end

    @testset "_wait_for_callback rejects state mismatch" begin
        port = GoogleAuth._free_port()
        task = @async GoogleAuth._wait_for_callback(port, "GOOD", 10)
        sleep(0.3)
        HTTP.get("http://127.0.0.1:$port/?code=X&state=BAD"; status_exception=false)
        @test_throws Exception fetch(task)
    end

    @testset "_wait_for_callback OAuth error param" begin
        port = GoogleAuth._free_port()
        task = @async GoogleAuth._wait_for_callback(port, "S", 10)
        sleep(0.3)
        HTTP.get("http://127.0.0.1:$port/?error=access_denied"; status_exception=false)
        @test_throws Exception fetch(task)
    end

    @testset "_wait_for_callback times out" begin
        port = GoogleAuth._free_port()
        task = @async GoogleAuth._wait_for_callback(port, "S", 1)  # 1 s
        @test_throws Exception fetch(task)
    end

    # ── OAuth: token exchange ───────────────────────────────
    @testset "_exchange_code posts correct form and parses response" begin
        port = GoogleAuth._free_port()
        received = Ref{Dict{String,String}}()
        server = HTTP.serve!(port) do req
            params = Dict{String,String}()
            for kv in split(String(req.body), '&')
                isempty(kv) && continue
                k, v = split(kv, '='; limit=2)
                params[String(k)] = URIs.unescapeuri(String(v))
            end
            received[] = params
            HTTP.Response(200, ["Content-Type" => "application/json"],
                """{"access_token":"AT","expires_in":3600,"refresh_token":"RT","token_type":"Bearer"}""")
        end
        try
            resp = GoogleAuth._exchange_code(;
                client_id="cid", client_secret="csec", code="CODE",
                code_verifier="VER", redirect_uri="http://127.0.0.1/",
                token_endpoint="http://127.0.0.1:$port/",
            )
            @test String(resp[:access_token])  == "AT"
            @test String(resp[:refresh_token]) == "RT"
            @test resp[:expires_in]            == 3600
            @test received[]["grant_type"]    == "authorization_code"
            @test received[]["code"]          == "CODE"
            @test received[]["client_id"]     == "cid"
            @test received[]["client_secret"] == "csec"
            @test received[]["code_verifier"] == "VER"
            @test received[]["redirect_uri"]  == "http://127.0.0.1/"
        finally
            close(server)
        end
    end

    @testset "_exchange_code raises on non-200" begin
        port = GoogleAuth._free_port()
        server = HTTP.serve!(port) do req
            HTTP.Response(400, """{"error":"invalid_grant"}""")
        end
        try
            @test_throws Exception GoogleAuth._exchange_code(;
                client_id="c", client_secret="s", code="x",
                code_verifier="v", redirect_uri="http://x/",
                token_endpoint="http://127.0.0.1:$port/",
            )
        finally
            close(server)
        end
    end

    # ── OAuth: end-to-end with mocked token endpoint ────────
    @testset "authorize_via_browser end-to-end (mocked)" begin
        token_port = GoogleAuth._free_port()
        token_server = HTTP.serve!(token_port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"],
                """{"access_token":"E2E_AT","expires_in":3600,"refresh_token":"E2E_RT","token_type":"Bearer"}""")
        end

        callback_port = GoogleAuth._free_port()
        fixed_state = "fixed-state-for-test"

        # Suppress the URL print by redirecting to devnull just for this call.
        auth_task = @async redirect_stdout(devnull) do
            authorize_via_browser(;
                client_id="test-client",
                client_secret="test-secret",
                scopes=["scope1"],
                port=callback_port,
                open_browser=false,
                token_endpoint="http://127.0.0.1:$token_port/",
                state=fixed_state,
                timeout=10,
            )
        end

        try
            sleep(0.3)  # let the callback server bind
            HTTP.get("http://127.0.0.1:$callback_port/?code=E2E_CODE&state=$fixed_state")

            creds = fetch(auth_task)
            @test creds isa CachedCredentials
            @test creds.inner isa UserCredentials
            @test creds.inner.refresh_token == "E2E_RT"
            @test creds.inner.client_id == "test-client"
            @test creds.inner.client_secret == "test-secret"
        finally
            close(token_server)
        end
    end

    @testset "authorize_via_browser persists ADC when save_adc=true" begin
        token_port = GoogleAuth._free_port()
        token_server = HTTP.serve!(token_port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"],
                """{"access_token":"AT","expires_in":3600,"refresh_token":"PERSISTED_RT","token_type":"Bearer"}""")
        end
        callback_port = GoogleAuth._free_port()
        fixed_state = "save-adc-state"

        # Redirect HOME so the well-known path lands in a temp dir we control.
        tmp_home = mktempdir()
        old_home = get(ENV, "HOME", nothing)
        ENV["HOME"] = tmp_home
        try
            auth_task = @async redirect_stdout(devnull) do
                authorize_via_browser(;
                    client_id="cid", client_secret="csec",
                    scopes=["scope1"],
                    port=callback_port, open_browser=false,
                    token_endpoint="http://127.0.0.1:$token_port/",
                    state=fixed_state, save_adc=true, timeout=10,
                )
            end
            sleep(0.3)
            HTTP.get("http://127.0.0.1:$callback_port/?code=X&state=$fixed_state")
            creds = fetch(auth_task)
            @test creds.inner.refresh_token == "PERSISTED_RT"

            adc_path = joinpath(tmp_home, ".config", "gcloud", "application_default_credentials.json")
            @test isfile(adc_path)
            payload = JSON3.read(read(adc_path, String))
            @test String(payload["type"])          == "authorized_user"
            @test String(payload["refresh_token"]) == "PERSISTED_RT"
            @test String(payload["client_id"])     == "cid"
        finally
            if old_home === nothing
                delete!(ENV, "HOME")
            else
                ENV["HOME"] = old_home
            end
            rm(tmp_home; recursive=true, force=true)
            close(token_server)
        end
    end
end
