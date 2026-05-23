# %% [markdown]
# # GoogleCloud2.jl Practical Workflow Test
# 
# このノートブックは `config.json` を読み込み、Google Cloud上にテスト用のリソースを自動構築した上で、
# 開発中の `GoogleCloud2.jl` ライブラリを使って実機検証を行います。
# 
# **事前準備:**
# 1. Google Cloud 上に検証用のプロジェクト（無料枠を利用）を作成する
# 2. `gcloud auth application-default login` でローカルADC認証を済ませる
# 3. `config.json` の `project_id` と `bucket_name`（世界で一意である必要あり）を修正する

# %%
using JSON3
using Pkg

# プロジェクトのルートディレクトリの環境を有効化
Pkg.activate("..")

using GoogleAuth
using GoogleCloudStorage
using BigQuery
using GoogleCloudPubSub

# %% [markdown]
# ## 1. 設定の読み込みと自動プロビジョニング
# `config.json` から設定を読み込み、`gcloud` および `bq` コマンドを用いてリソースを自動作成します。
# 既に存在する場合はスキップされるように idempotent（冪等）なコマンドを使用します。

# %%
config_path = "config.json"
config = JSON3.read(read(config_path, String))

project_id = config.project_id
location = config.location
bucket_name = config.storage.bucket_name
dataset_id = config.bigquery.dataset_id
topic_id = config.pubsub.topic_id

println("=== Provisioning GCP Resources ===")
println("Project ID: $project_id")

# %% [markdown]
# ### Storage バケットの作成
# %%
try
    run(`gcloud storage buckets create gs://$bucket_name --project=$project_id --location=$location`)
    println("✅ Bucket created: $bucket_name")
catch e
    println("⚠️ Bucket already exists or failed to create. Proceeding...")
end

# %% [markdown]
# ### BigQuery データセットとテーブルの作成
# %%
try
    run(`bq --project_id=$project_id mk --dataset --location=$location $dataset_id`)
    println("✅ Dataset created: $dataset_id")
catch e
    println("⚠️ Dataset already exists or failed to create. Proceeding...")
end

for table in config.bigquery.tables
    t_id = table.table_id
    schema = table.schema
    try
        run(`bq --project_id=$project_id mk --table $dataset_id.$t_id $schema`)
        println("✅ Table created: $t_id")
    catch e
        println("⚠️ Table already exists or failed to create. Proceeding...")
    end
end

# %% [markdown]
# ### Pub/Sub トピックの作成
# %%
try
    run(`gcloud pubsub topics create $topic_id --project=$project_id`)
    println("✅ Topic created: $topic_id")
catch e
    println("⚠️ Topic already exists or failed to create. Proceeding...")
end

println("\n🎉 Provisioning Complete!")

# %% [markdown]
# ## 2. ライブラリ (GoogleCloud2.jl) を用いた実動作テスト
# リソースが準備できたので、ここから先は今回開発している Julia ライブラリを使ってアクセスします。

# %%
# 認証情報の取得（Application Default Credentials）
println("--- 認証情報の取得 ---")
creds = get_application_default()
println("認証成功: ", typeof(creds))

# %%
# Cloud Storage へのアクセス
println("\n--- Cloud Storage 検証 ---")
# ※ 現在のGoogleCloudStorageモジュールはプロトタイプ実装です
storage_client = GoogleCloudStorage.Client(project_id)
bucket = GoogleCloudStorage.get_bucket(storage_client, bucket_name)
println("取得したバケット名: ", bucket.name)

# %%
# BigQuery へのアクセス
println("\n--- BigQuery 検証 ---")
# ※ Arrow.jl を用いたクエリ発行のプロトタイプ実装
bq_client = BigQuery.BQClient(project_id)
query = "SELECT CURRENT_TIMESTAMP() as now, 'Hello from Julia' as message"
result_table = BigQuery.query_arrow(bq_client, query)
println("BigQuery クエリ実行完了")

# %%
# Pub/Sub へのアクセス
println("\n--- Pub/Sub 検証 ---")
pubsub_client = PubSubClient(project=project_id, endpoint="https://pubsub.googleapis.com")
# 実環境でトピックを作成/取得する処理
# ※ GCP環境に対して直接リクエストを飛ばすため、通信ロジックが実装されている必要があります。
# topic = create_topic(pubsub_client, topic_id)
println("PubSub クライアント初期化完了")

# %% [markdown]
# ## 3. リソースのクリーンアップ（オプション）
# 使い終わったダミーリソースを削除して、課金を完全に防ぎます。

# %%
# 以下のフラグを true にするとリソースが削除されます
RUN_CLEANUP = false

if RUN_CLEANUP
    println("=== Cleaning up GCP Resources ===")
    
    # Bucketの削除
    try run(`gcloud storage rm --recursive gs://$bucket_name`); catch; end
    
    # Datasetの削除
    try run(`bq --project_id=$project_id rm -r -f $dataset_id`); catch; end
    
    # Topicの削除
    try run(`gcloud pubsub topics delete $topic_id --project=$project_id`); catch; end
    
    println("🎉 Cleanup Complete!")
end
