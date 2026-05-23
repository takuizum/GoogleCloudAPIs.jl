# GoogleCloudAPIs.jl — Practical Workflow Example
#
# Demonstrates the full API surface against a real GCP project using ADC.
#
# Pre-requisites:
#   1. Authenticate: gcloud auth application-default login
#   2. Set PROJECT_ID below or export the env variable GOOGLE_CLOUD_PROJECT.
#   3. Run: julia --project=.. examples/01_practical_workflow.jl
#
# Nothing is committed to git from this directory.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

import GoogleAuth
import BigQuery
import GoogleCloudStorage
import GoogleCloudPubSub
using Dates

const PROJECT_ID = get(ENV, "GOOGLE_CLOUD_PROJECT", "YOUR_PROJECT_ID")

function section(title)
    println("\n" * "─"^50)
    println("  $title")
    println("─"^50)
end

println("=== GoogleCloudAPIs.jl practical workflow (project=$PROJECT_ID) ===")

# ─────────────────────────────────────────────────────────────
# 1. Authentication — Application Default Credentials
# ─────────────────────────────────────────────────────────────
section("Auth")
creds = GoogleAuth.get_application_default()
token = GoogleAuth.get_token(creds)
println("  token_type=$(token.token_type), expires_in=$(token.expires_in)s")

# ─────────────────────────────────────────────────────────────
# 2. BigQuery — simple query
# ─────────────────────────────────────────────────────────────
section("BigQuery: simple query")
bq = BigQuery.BQClient(PROJECT_ID; creds=creds)

rows = BigQuery.query(bq, "SELECT 1 AS num, 'hello' AS msg")
println("  SELECT 1 => $(rows[1])")

# Arrow format (client-side JSON→Arrow conversion)
tbl = BigQuery.query(bq, "SELECT 1 AS x, 'a' AS s UNION ALL SELECT 2, 'b'"; format=:arrow)
println("  Arrow rows: $(length(collect(tbl.x)))")

# ─────────────────────────────────────────────────────────────
# 3. BigQuery — dataset + table CRUD
# ─────────────────────────────────────────────────────────────
section("BigQuery: dataset + table lifecycle")

suffix = lowercase(string(round(Int, time()), base=16))
ds_id  = "gc2jl_example_$(suffix)"
tbl_id = "events"

try
    ds = BigQuery.create_dataset(bq, ds_id; location="US")
    println("  create_dataset => $(ds.dataset_id) ($(ds.location))")

    schema = [
        BigQuery.TableFieldSchema("id",   "INT64";  mode="REQUIRED"),
        BigQuery.TableFieldSchema("name", "STRING"),
        BigQuery.TableFieldSchema("ts",   "TIMESTAMP"),
    ]
    t = BigQuery.create_table(bq, ds_id, tbl_id, schema)
    println("  create_table   => $(t.table_id) ($(length(t.schema)) fields)")

    listed = collect(BigQuery.list_tables(bq, ds_id))
    println("  list_tables    => $(length(listed)) table(s)")

    BigQuery.query(bq, """
        INSERT INTO `$PROJECT_ID.$ds_id.$tbl_id` (id, name, ts)
        VALUES (1, 'Alice', CURRENT_TIMESTAMP()),
               (2, 'Bob',   CURRENT_TIMESTAMP())
    """)
    println("  INSERT OK")

    result = BigQuery.query(bq, "SELECT id, name FROM `$PROJECT_ID.$ds_id.$tbl_id` ORDER BY id")
    println("  SELECT => $([r.name for r in result])")
finally
    try; BigQuery.delete_table(bq, ds_id, tbl_id);            println("  delete_table OK");   catch; end
    try; BigQuery.delete_dataset(bq, ds_id; delete_contents=true); println("  delete_dataset OK"); catch; end
end

# ─────────────────────────────────────────────────────────────
# 4. Cloud Storage — bucket + object lifecycle
# ─────────────────────────────────────────────────────────────
section("Cloud Storage: bucket + object lifecycle")
gcs = GoogleCloudStorage.Client(PROJECT_ID; creds=creds)

bucket_name = "gc2jl-example-$(PROJECT_ID)-$(suffix)"[1:min(end, 63)]

try
    b = GoogleCloudStorage.create_bucket(gcs, bucket_name; location="US")
    println("  create_bucket  => $(b.name)")

    payload = "Hello from GoogleCloudAPIs.jl @ $(now())"
    obj = GoogleCloudStorage.upload_object(gcs, bucket_name, "hello.txt",
                                           payload; content_type="text/plain")
    println("  upload_object  => $(obj.name) ($(obj.size) bytes)")

    downloaded = GoogleCloudStorage.download_object(gcs, bucket_name, "hello.txt")
    @assert String(downloaded) == payload
    println("  download_object matches")

    GoogleCloudStorage.upload_object(gcs, bucket_name, "data.bin", UInt8[0xDE, 0xAD, 0xBE, 0xEF])
    bytes_back = GoogleCloudStorage.download_object(gcs, bucket_name, "data.bin")
    @assert bytes_back == UInt8[0xDE, 0xAD, 0xBE, 0xEF]
    println("  binary round-trip OK")

    objs = collect(GoogleCloudStorage.list_objects(gcs, bucket_name))
    println("  list_objects   => $(length(objs)) object(s)")

    md = GoogleCloudStorage.get_object(gcs, bucket_name, "hello.txt")
    println("  get_object     => content_type=$(md.content_type)")

    for o in objs
        GoogleCloudStorage.delete_object(gcs, bucket_name, o.name)
    end
    println("  delete_object  x$(length(objs))")
finally
    try; GoogleCloudStorage.delete_bucket(gcs, bucket_name); println("  delete_bucket OK"); catch; end
end

# ─────────────────────────────────────────────────────────────
# 5. Pub/Sub — topic + subscription + publish + pull
# ─────────────────────────────────────────────────────────────
section("Pub/Sub: topic + subscription + publish + pull")
ps = GoogleCloudPubSub.PubSubClient(project=PROJECT_ID, creds=creds)

topic_id = "gc2jl-example-topic-$suffix"
sub_id   = "gc2jl-example-sub-$suffix"

# Pre-flight: skip cleanly if Pub/Sub API is not enabled
try
    GoogleCloudPubSub.list_topics(ps) |> iterate
catch e
    if occursin("SERVICE_DISABLED", sprint(showerror, e)) ||
       occursin("has not been used in project", sprint(showerror, e))
        @warn "Pub/Sub API is not enabled on $(PROJECT_ID). Enable it in the GCP Console."
        println("\n=== Workflow complete (Pub/Sub skipped) ===")
        exit(0)
    else
        rethrow(e)
    end
end

try
    topic = GoogleCloudPubSub.create_topic(ps, topic_id)
    println("  create_topic   => $(topic.name)")

    sub = GoogleCloudPubSub.create_subscription(ps, sub_id, topic_id; ack_deadline_seconds=30)
    println("  create_sub     => $(sub.name)")

    # Single publish
    mid = GoogleCloudPubSub.publish(ps, topic_id, "hello from julia";
                                    attributes=Dict("src" => "example"))
    println("  publish single => $mid")

    # Batch publish
    ids = GoogleCloudPubSub.publish(ps, topic_id, [
        GoogleCloudPubSub.PubSubMessage("batch-1"),
        GoogleCloudPubSub.PubSubMessage("batch-2"; attributes=Dict("priority" => "low")),
    ])
    println("  publish batch  => $(length(ids)) ids")

    # Pull with retries
    received = GoogleCloudPubSub.PubSubMessage[]
    for _ in 1:10
        batch = GoogleCloudPubSub.pull(ps, sub_id; max_messages=10, return_immediately=true)
        append!(received, batch)
        length(received) >= 3 && break
        sleep(1)
    end
    println("  pull           => $(length(received)) message(s)")

    ack_ids = [m.ack_id for m in received if m.ack_id !== nothing]
    if !isempty(ack_ids)
        GoogleCloudPubSub.acknowledge(ps, sub_id, ack_ids)
        println("  acknowledge    => $(length(ack_ids)) ack_id(s)")
    end

    for m in received
        println("    data=$(String(m.data))  attrs=$(m.attributes)")
    end
finally
    try; GoogleCloudPubSub.delete_subscription(ps, sub_id);   println("  delete_sub OK");   catch; end
    try; GoogleCloudPubSub.delete_topic(ps, topic_id);         println("  delete_topic OK"); catch; end
end

println("\n=== All examples completed successfully ===")
