using Test
using BigQuery
using Arrow
using Base64
using Dates
using HTTP
using JSON
using Aqua
import Sockets
import GoogleApiCore
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
struct MockBQCreds <: GoogleAuth.Credentials end
get_token(::MockBQCreds) = GoogleAuth.Token("mock-bq-token", 3600, "Bearer")

# Build a BQ jobs.query response with JSON rows for integer column x.
function bq_integer_response(; x_values=Int64[1, 2, 3])
    row_list = [Dict("f" => [Dict("v" => string(v))]) for v in x_values]
    JSON.json(Dict(
        "jobComplete" => true,
        "jobReference" => Dict("projectId" => "proj", "jobId" => "job-mock"),
        "schema" => Dict("fields" => [Dict("name" => "x", "type" => "INTEGER")]),
        "rows" => row_list,
    ))
end

# Build a BQ jobs.query response with JSON rows.
# rows: Vector of Vectors of values (converted to String by the helper)
# fields: Vector of (name, BQ_TYPE) tuples
function bq_json_response(; rows=[[1, "a"], [2, "b"]],
                            fields=[("n", "INTEGER"), ("s", "STRING")])
    field_defs = [Dict("name" => nm, "type" => tp) for (nm, tp) in fields]
    row_list   = [Dict("f" => [Dict("v" => string(v)) for v in row]) for row in rows]
    JSON.json(Dict(
        "jobComplete" => true,
        "jobReference" => Dict("projectId" => "proj", "jobId" => "job-mock"),
        "schema" => Dict("fields" => field_defs),
        "rows"   => row_list,
    ))
end

# ────────────────────────────────────────────────────────────
@testset "BigQuery.jl" begin

    @testset "Aqua" begin
        Aqua.test_all(BigQuery; ambiguities=false, persistent_tasks=false)
    end

    # ── _coerce_value: type conversions ──────────────────────
    @testset "_coerce_value type coercions" begin
        cv = BigQuery._coerce_value
        @test cv("42",    "INTEGER") === Int64(42)
        @test cv("99",    "INT64")   === Int64(99)
        @test cv("3.14",  "FLOAT")   ≈   3.14
        @test cv("2.718", "FLOAT64") ≈   2.718
        @test cv("true",  "BOOLEAN") === true
        @test cv("false", "BOOL")    === false
        @test cv("hello", "STRING")  == "hello"
        @test cv(nothing, "INTEGER") === missing
        @test cv(nothing, "STRING")  === missing
    end

    @testset "_coerce_value temporal types" begin
        cv = BigQuery._coerce_value

        # TIMESTAMP: epoch-seconds decimal string, scientific notation included
        @test cv("1.7297836E9", "TIMESTAMP") == Dates.unix2datetime(1.7297836e9)
        ts = cv("1729783600.123456", "TIMESTAMP")
        @test ts isa DateTime
        @test Dates.millisecond(ts) == 123       # µs は切り捨て

        @test cv("2026-06-13", "DATE") == Date(2026, 6, 13)

        @test cv("2026-06-13T12:34:56", "DATETIME") ==
              DateTime(2026, 6, 13, 12, 34, 56)
        @test cv("2026-06-13T12:34:56.789123", "DATETIME") ==
              DateTime(2026, 6, 13, 12, 34, 56, 789)   # µs は切り捨て

        t = cv("12:34:56.789123", "TIME")
        @test t == Time(12, 34, 56) + Millisecond(789) + Microsecond(123)
        @test cv("01:02:03", "TIME") == Time(1, 2, 3)

        # null → missing
        @test cv(nothing, "TIMESTAMP") === missing
        @test cv(nothing, "DATE") === missing
    end

    @testset "_coerce_value bytes / numeric / record / repeated" begin
        cv = BigQuery._coerce_value
        BQField = BigQuery.BQField

        # BYTES → base64 decode
        @test cv(Base64.base64encode("hello"), "BYTES") == Vector{UInt8}("hello")

        # NUMERIC/BIGNUMERIC は精度保持のため String のまま（回帰テスト）
        @test cv("12345678901234567890.123456789", "NUMERIC") ==
              "12345678901234567890.123456789"
        @test cv("1.5", "BIGNUMERIC") == "1.5"

        # RECORD → ネスト NamedTuple
        rec_field = BQField(:r, "RECORD"; fields=[
            BQField(:a, "INT64"), BQField(:b, "STRING"),
        ])
        raw_rec = Dict("f" => [Dict("v" => "42"), Dict("v" => "x")])
        @test cv(raw_rec, rec_field) == (a = 42, b = "x")

        # REPEATED INT64 → Vector{Int64}
        rep_field = BQField(:xs, "INT64"; mode="REPEATED")
        @test cv([Dict("v" => "1"), Dict("v" => "2")], rep_field) == [1, 2]

        # REPEATED RECORD → Vector{NamedTuple}
        rep_rec = BQField(:rs, "RECORD"; mode="REPEATED",
                          fields=[BQField(:a, "INT64")])
        raw = [Dict("v" => Dict("f" => [Dict("v" => "7")])),
               Dict("v" => Dict("f" => [Dict("v" => "8")]))]
        @test cv(raw, rep_rec) == [(a = 7,), (a = 8,)]

        # GEOGRAPHY などの未知型は String のまま
        @test cv("POINT(1 2)", "GEOGRAPHY") == "POINT(1 2)"
    end

    @testset "_parse_schema: mode and nested fields" begin
        page = Dict("schema" => Dict("fields" => [
            Dict("name" => "id", "type" => "INT64", "mode" => "REQUIRED"),
            Dict("name" => "tags", "type" => "STRING", "mode" => "REPEATED"),
            Dict("name" => "addr", "type" => "RECORD", "fields" => [
                Dict("name" => "city", "type" => "STRING"),
            ]),
        ]))
        fields = BigQuery._parse_schema(page)
        @test length(fields) == 3
        @test fields[1].name == :id   && fields[1].mode == "REQUIRED"
        @test fields[2].mode == "REPEATED"
        @test fields[3].type == "RECORD"
        @test fields[3].fields[1].name == :city
        @test fields[1].fields == BigQuery.BQField[]
        @test fields[3].mode == "NULLABLE"   # mode 省略時のデフォルト
        @test BigQuery._parse_schema(Dict()) == BigQuery.BQField[]
    end

    @testset "query with typed columns end-to-end (mock server)" begin
        port = free_port()
        body = JSON.json(Dict(
            "jobComplete" => true,
            "jobReference" => Dict("projectId" => "proj", "jobId" => "job-typed"),
            "schema" => Dict("fields" => [
                Dict("name" => "ts",   "type" => "TIMESTAMP"),
                Dict("name" => "d",    "type" => "DATE"),
                Dict("name" => "blob", "type" => "BYTES"),
                Dict("name" => "tags", "type" => "INT64", "mode" => "REPEATED"),
                Dict("name" => "rec",  "type" => "RECORD", "fields" => [
                    Dict("name" => "city", "type" => "STRING"),
                ]),
                Dict("name" => "maybe", "type" => "STRING"),
            ]),
            "rows" => [Dict("f" => [
                Dict("v" => "1729783600.5"),
                Dict("v" => "2026-06-13"),
                Dict("v" => Base64.base64encode("bin")),
                Dict("v" => [Dict("v" => "1"), Dict("v" => "2")]),
                Dict("v" => Dict("f" => [Dict("v" => "Tokyo")])),
                Dict("v" => nothing),
            ])],
        ))
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("proj", nothing, "http://127.0.0.1:$port", true, "US")
            rows = query(client, "SELECT * FROM t")
            @test length(rows) == 1
            r = rows[1]
            @test r.ts == Dates.unix2datetime(1729783600.5)
            @test r.d == Date(2026, 6, 13)
            @test r.blob == Vector{UInt8}("bin")
            @test r.tags == [1, 2]
            @test r.rec == (city = "Tokyo",)
            @test r.maybe === missing
        finally
            close(server)
        end
    end

    @testset "format=:arrow with temporal and missing columns (smoke)" begin
        port = free_port()
        body = JSON.json(Dict(
            "jobComplete" => true,
            "jobReference" => Dict("projectId" => "proj", "jobId" => "job-arrow2"),
            "schema" => Dict("fields" => [
                Dict("name" => "ts", "type" => "TIMESTAMP"),
                Dict("name" => "s",  "type" => "STRING"),
            ]),
            "rows" => [
                Dict("f" => [Dict("v" => "1729783600"), Dict("v" => "a")]),
                Dict("f" => [Dict("v" => "1729783601"), Dict("v" => nothing)]),
            ],
        ))
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("proj", nothing, "http://127.0.0.1:$port", true, "US")
            tbl = query(client, "SELECT ts, s FROM t"; format=:arrow)
            @test tbl isa Arrow.Table
            @test collect(tbl.ts) == [Dates.unix2datetime(1729783600),
                                      Dates.unix2datetime(1729783601)]
            @test collect(tbl.s)[1] == "a"
            @test collect(tbl.s)[2] === missing
        finally
            close(server)
        end
    end

    # ── _rows_to_arrow: client-side JSON→Arrow.Table conversion ─
    @testset "_rows_to_arrow round-trip" begin
        rows = [(x = Int64(1), y = "a"), (x = Int64(2), y = "b"), (x = Int64(3), y = "c")]
        tbl = BigQuery._rows_to_arrow(rows)
        @test tbl isa Arrow.Table
        @test collect(tbl.x) == [1, 2, 3]
        @test collect(tbl.y) == ["a", "b", "c"]
    end

    # ── query format=:arrow via mock HTTP server ─────────────
    # Arrow is now a client-side conversion from JSON; the mock returns JSON rows.
    @testset "query format=:arrow (mock server, client-side conversion)" begin
        port = free_port()
        body = bq_integer_response(; x_values=Int64[10, 20, 30])
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("proj", nothing, "http://127.0.0.1:$port", true, "US")
            tbl = query(client, "SELECT x FROM t"; format=:arrow)
            @test tbl isa Arrow.Table
            @test collect(tbl.x) == [10, 20, 30]
        finally
            close(server)
        end
    end

    # ── query format=:json via mock HTTP server ──────────────
    @testset "query format=:json (mock server)" begin
        port = free_port()
        body = bq_json_response(; rows=[[7, "foo"], [8, "bar"]],
                                   fields=[("n", "INTEGER"), ("s", "STRING")])
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("proj", nothing, "http://127.0.0.1:$port", true, "US")
            rows = query(client, "SELECT n, s FROM t"; format=:json)
            @test length(rows) == 2
            @test rows[1].n == 7
            @test rows[1].s == "foo"
            @test rows[2].n == 8
            @test rows[2].s == "bar"
        finally
            close(server)
        end
    end

    # ── Authorization header is injected for non-emulator ────
    @testset "BQClient injects Authorization header" begin
        received_headers = Ref{HTTP.Headers}()
        port = free_port()
        body = bq_json_response()
        server = HTTP.serve!(port) do req
            received_headers[] = req.headers
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            # is_emulator=false → auth header should be added
            client = BQClient("proj", MockBQCreds(), "http://127.0.0.1:$port", false, "US")
            query(client, "SELECT 1"; format=:json)
            @test any(h -> h[1] == "Authorization" && h[2] == "Bearer mock-bq-token",
                      received_headers[])
        finally
            close(server)
        end
    end

    # ── job polling: schema from first complete page ─────────
    @testset "query polls until jobComplete (mock server)" begin
        port = free_port()
        hits = Ref(0)
        incomplete = JSON.json(Dict(
            "jobComplete"  => false,
            "jobReference" => Dict("projectId" => "proj", "jobId" => "job-poll"),
        ))
        complete = bq_integer_response(; x_values=Int64[5, 6])
        server = HTTP.serve!(port) do _req
            hits[] += 1
            HTTP.Response(200, ["Content-Type" => "application/json"],
                          hits[] == 1 ? incomplete : complete)
        end
        try
            client = BQClient("proj", nothing, "http://127.0.0.1:$port", true, "US")
            rows = query(client, "SELECT x FROM t"; poll_timeout=10.0)
            # スキーマは最初の complete ページから取得される（incomplete ページに
            # schema は無い）
            @test [r.x for r in rows] == [5, 6]
            @test hits[] >= 2
        finally
            close(server)
        end
    end

    @testset "query poll_timeout throws TimeoutError (mock server)" begin
        port = free_port()
        stuck = JSON.json(Dict(
            "jobComplete"  => false,
            "jobReference" => Dict("projectId" => "proj", "jobId" => "job-stuck"),
        ))
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], stuck)
        end
        try
            client = BQClient("proj", nothing, "http://127.0.0.1:$port", true, "US")
            t = @elapsed @test_throws GoogleApiCore.TimeoutError query(
                client, "SELECT 1"; poll_timeout=0.5)
            @test t < 5.0
        finally
            close(server)
        end
    end

    # ── Paginated JSON result: mock returns two pages ─────────
    @testset "query format=:json multi-page (mock server)" begin
        port = free_port()
        page1 = JSON.json(Dict(
            "jobComplete" => true,
            "jobReference" => Dict("projectId" => "proj", "jobId" => "job1"),
            "schema" => Dict("fields" => [Dict("name" => "n", "type" => "INTEGER")]),
            "rows"   => [Dict("f" => [Dict("v" => "1")]),
                         Dict("f" => [Dict("v" => "2")])],
            "pageToken" => "tok2",
        ))
        page2 = JSON.json(Dict(
            "jobComplete" => true,
            "jobReference" => Dict("projectId" => "proj", "jobId" => "job1"),
            "schema" => Dict("fields" => [Dict("name" => "n", "type" => "INTEGER")]),
            "rows"   => [Dict("f" => [Dict("v" => "3")])],
        ))
        idx = Ref(0)
        server = HTTP.serve!(port) do _req
            idx[] += 1
            body = idx[] == 1 ? page1 : page2
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("proj", nothing, "http://127.0.0.1:$port", true, "US")
            rows = query(client, "SELECT n FROM t"; format=:json)
            @test length(rows) == 3
            @test [r.n for r in rows] == [1, 2, 3]
        finally
            close(server)
        end
    end

    # ── Dataset CRUD (mock server) ───────────────────────────
    @testset "list_datasets (mock)" begin
        port = free_port()
        body = JSON.json(Dict(
            "datasets" => [
                Dict("datasetReference" => Dict("projectId" => "p", "datasetId" => "d1"),
                     "location" => "US"),
                Dict("datasetReference" => Dict("projectId" => "p", "datasetId" => "d2"),
                     "location" => "EU"),
            ],
        ))
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("p", nothing, "http://127.0.0.1:$port", true, "US")
            datasets = collect(list_datasets(client))
            @test length(datasets) == 2
            @test datasets[1].dataset_id == "d1"
            @test datasets[1].location   == "US"
            @test datasets[2].dataset_id == "d2"
        finally
            close(server)
        end
    end

    @testset "get_dataset (mock)" begin
        port = free_port()
        body = JSON.json(Dict(
            "datasetReference" => Dict("projectId" => "p", "datasetId" => "ds1"),
            "location" => "asia-northeast1",
            "friendlyName" => "My Dataset",
        ))
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("p", nothing, "http://127.0.0.1:$port", true, "US")
            ds = get_dataset(client, "ds1")
            @test ds.dataset_id    == "ds1"
            @test ds.location      == "asia-northeast1"
            @test ds.friendly_name == "My Dataset"
        finally
            close(server)
        end
    end

    @testset "create_dataset (mock)" begin
        port = free_port()
        received_body = Ref{Vector{UInt8}}()
        body = JSON.json(Dict(
            "datasetReference" => Dict("projectId" => "p", "datasetId" => "new-ds"),
            "location" => "US",
        ))
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("p", nothing, "http://127.0.0.1:$port", true, "US")
            ds = create_dataset(client, "new-ds")
            @test ds.dataset_id == "new-ds"
            doc = JSON.parse(IOBuffer(received_body[]))
            @test String(doc["datasetReference"]["datasetId"]) == "new-ds"
            @test String(doc["location"]) == "US"
        finally
            close(server)
        end
    end

    @testset "delete_dataset (mock)" begin
        port = free_port()
        received_method = Ref{String}()
        received_path = Ref{String}()
        server = HTTP.serve!(port) do req
            received_method[] = req.method
            received_path[]   = req.target
            HTTP.Response(204, "")
        end
        try
            client = BQClient("p", nothing, "http://127.0.0.1:$port", true, "US")
            @test delete_dataset(client, "ds1"; delete_contents=true) === nothing
            @test received_method[] == "DELETE"
            @test occursin("deleteContents=true", received_path[])
        finally
            close(server)
        end
    end

    # ── Table CRUD (mock server) ─────────────────────────────
    @testset "create_table + get_table (mock)" begin
        port = free_port()
        received_body = Ref{Vector{UInt8}}()
        body = JSON.json(Dict(
            "tableReference" => Dict("projectId" => "p", "datasetId" => "d",
                                     "tableId" => "t1"),
            "schema" => Dict("fields" => [
                Dict("name" => "id",   "type" => "INT64",  "mode" => "REQUIRED"),
                Dict("name" => "name", "type" => "STRING", "mode" => "NULLABLE"),
            ]),
        ))
        server = HTTP.serve!(port) do req
            received_body[] = req.body
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("p", nothing, "http://127.0.0.1:$port", true, "US")
            schema = [
                TableFieldSchema("id",   "INT64";  mode="REQUIRED"),
                TableFieldSchema("name", "STRING"),
            ]
            tbl = create_table(client, "d", "t1", schema)
            @test tbl.table_id == "t1"
            @test length(tbl.schema) == 2
            @test tbl.schema[1].name == "id"
            @test tbl.schema[1].mode == "REQUIRED"
            doc = JSON.parse(IOBuffer(received_body[]))
            @test String(doc["tableReference"]["tableId"]) == "t1"
            @test length(doc["schema"]["fields"]) == 2
        finally
            close(server)
        end
    end

    @testset "list_tables (mock)" begin
        port = free_port()
        body = JSON.json(Dict(
            "tables" => [
                Dict("tableReference" => Dict("projectId" => "p", "datasetId" => "d",
                                              "tableId" => "t1"), "numRows" => "100"),
                Dict("tableReference" => Dict("projectId" => "p", "datasetId" => "d",
                                              "tableId" => "t2")),
            ],
        ))
        server = HTTP.serve!(port) do _req
            HTTP.Response(200, ["Content-Type" => "application/json"], body)
        end
        try
            client = BQClient("p", nothing, "http://127.0.0.1:$port", true, "US")
            tables = collect(list_tables(client, "d"))
            @test length(tables) == 2
            @test tables[1].table_id == "t1"
            @test tables[1].num_rows == 100
            @test tables[2].table_id == "t2"
            @test tables[2].num_rows === nothing
        finally
            close(server)
        end
    end

    @testset "delete_table (mock)" begin
        port = free_port()
        received_method = Ref{String}()
        server = HTTP.serve!(port) do req
            received_method[] = req.method
            HTTP.Response(204, "")
        end
        try
            client = BQClient("p", nothing, "http://127.0.0.1:$port", true, "US")
            @test delete_table(client, "d", "t1") === nothing
            @test received_method[] == "DELETE"
        finally
            close(server)
        end
    end

    # ── Emulator integration tests ───────────────────────────
    started_container = nothing
    if !haskey(ENV, "BIGQUERY_EMULATOR_HOST")
        try
            HTTP.get("http://localhost:9050/discovery/v1/apis/bigquery/v2/rest"; readtimeout=2)
            ENV["BIGQUERY_EMULATOR_HOST"] = "http://localhost:9050"
            @info "Detected running BigQuery emulator on localhost:9050"
        catch
            container_name = "bq-emulator-test-$(rand(UInt32))"
            try
                @info "Starting BigQuery emulator..."
                run(`docker run -d --platform linux/amd64 --name $container_name -p 9050:9050 ghcr.io/goccy/bigquery-emulator:0.4.3 bigquery-emulator --project=test-project --port=9050`)
                connected = false
                for _ in 1:15
                    try
                        HTTP.get("http://localhost:9050/discovery/v1/apis/bigquery/v2/rest"; readtimeout=2)
                        connected = true
                        break
                    catch
                        sleep(2)
                    end
                end
                if connected
                    ENV["BIGQUERY_EMULATOR_HOST"] = "http://localhost:9050"
                    started_container = container_name
                else
                    @warn "BigQuery emulator failed to start. Skipping integration tests."
                end
            catch e
                @warn "Could not spin up BigQuery emulator ($e). Skipping integration tests."
            end
        end
    end

    if haskey(ENV, "BIGQUERY_EMULATOR_HOST")
        @info "Using BigQuery emulator at $(ENV["BIGQUERY_EMULATOR_HOST"])"
        client = BQClient("test-project")
        try
            @testset "query SELECT 1 (emulator JSON path)" begin
                rows = query(client, "SELECT 1 AS one"; format=:json)
                @test length(rows) == 1
                @test rows[1].one == 1
            end

            @testset "query multi-row (emulator JSON path)" begin
                rows = query(client, "SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3"; format=:json)
                @test length(rows) == 3
                @test sort([r.n for r in rows]) == [1, 2, 3]
            end

            @testset "dataset and table CRUD (emulator)" begin
                ds_id = "test_ds_$(rand(1000:9999))"
                tbl_id = "tbl_$(rand(1000:9999))"
                try
                    ds = create_dataset(client, ds_id)
                    @test ds.dataset_id == ds_id

                    ds_names = [d.dataset_id for d in list_datasets(client)]
                    @test ds_id in ds_names

                    got = get_dataset(client, ds_id)
                    @test got.dataset_id == ds_id

                    schema = [
                        TableFieldSchema("id",   "INT64"; mode="REQUIRED"),
                        TableFieldSchema("name", "STRING"),
                    ]
                    tbl = create_table(client, ds_id, tbl_id, schema)
                    @test tbl.table_id == tbl_id
                    @test length(tbl.schema) == 2

                    tables = collect(list_tables(client, ds_id))
                    @test any(t -> t.table_id == tbl_id, tables)

                    delete_table(client, ds_id, tbl_id)
                finally
                    try; delete_dataset(client, ds_id; delete_contents=true); catch; end
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
