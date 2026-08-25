### 3. TESTING.md (テスト設計と品質保証)

Agentがテストを自動実行・検証するための設計指針です。

# Test Design & Quality Assurance

## 1. Local Development with Emulators

実リソースへの課金と遅延を避けるため、GCPエミュレータを必須とする。

* **Tools**: 生の `docker` CLI（`Base.run` 経由の `docker run` / `docker compose`）でエミュレータを起動する。
  `Testcontainers.jl` は依存に含めていない — CI では `docker-compose.yml`
  （リポジトリ直下）をジョブレベルで起動し、ローカル実行時は各パッケージの
  `test/runtests.jl` が同じイメージを自前で `docker run` して個別に立ち上げる
  （`GoogleCloudStorage.jl/test/runtests.jl`, `GoogleBigQuery.jl/test/runtests.jl`,
  `GoogleCloudPubSub.jl/test/runtests.jl`）。Docker が使えない環境では起動失敗を
  `@warn` で捕捉し、統合テストをスキップして単体テストのみ実行する。
* **Environmental Toggle**: `PUBSUB_EMULATOR_HOST` / `STORAGE_EMULATOR_HOST` /
  `BIGQUERY_EMULATOR_HOST` を検知し、`GoogleApiCore.resolve_endpoint` が自動で
  非TLS/ローカル接続へ切り替える（CI ではジョブ環境変数で明示、ローカルでは
  テストコードが自分で起動したエミュレータのホストを渡す）。

## 2. Testing Levels

* **Unit Tests**: ネットワークIOを発生させないロジック検証に加え、`HTTP.jl` の
  `HTTP.serve!` でローカルにモックHTTPサーバーを立てて GET/POST の往復を検証する
  パターンを多用する（`Mocking.jl` のようなモンキーパッチ型モックは使っていない）。
* **Integration Tests**: 上記の Docker エミュレータに対して実際にリクエストを送る
  形で、GCS/BigQuery/Pub/Sub の CRUD・エラーパスを検証する。
* **Golden Tests**: 現状 `ReferenceTests.jl` によるレスポンスJSONの比較は未導入。
  スキーマ変更の検知は通常の `@test` によるフィールドアサーションに依っている。

## 3. CI/CD Integration

* GitHub Actions 上で `docker compose up -d` によりエミュレータを起動し、
  `JULIA_NUM_THREADS: auto` の環境でパッケージ単位・Juliaバージョン単位
  （1.10 / 1.11 / 1.12）にテストを並列実行する（`.github/workflows/CI.yml`）。
* `Aqua.jl` によるパッケージの健全性テスト（曖昧なエクスポートや依存関係の漏れをチェック）
  を、専用の `lint` ジョブとして本テストの前段で実行する。

## 4. Sample Test Snippet

```julia
using Test, HTTP, JSON, GoogleCloudPubSub

# モックHTTPサーバーの例（実際のテストで使われているパターン）
port = free_port()
server = HTTP.serve!(port) do req
    return HTTP.Response(200, ["Content-Type" => "application/json"],
                          JSON.json(Dict("messageIds" => ["mid-1"])))
end
try
    client = PubSubClient("p", nothing, "http://127.0.0.1:$port", true)
    mid = publish(client, "topic-a", "hello, world!")
    @test mid == "mid-1"
finally
    close(server)
end
```

Docker エミュレータを使った統合テストの例は
`GoogleCloudPubSub.jl/test/runtests.jl` の `docker run` 起動ブロックを参照。

---

### 4. 実装の優先順位

Agentに対して、以下の順序でタスクをアサインすることを推奨します：

1.  **フェーズ1**: `GoogleAuth.jl` の実装（ADCとメタデータサーバ連携の完遂）。
2.  **フェーズ2**: `GoogleApiCore.jl` での `AIP-158` (ページネーション) と指数バックオフの共通化。
3.  **フェーズ3**: `GoogleCloudStorage.jl` のプロトタイプ作成（`CloudStore.jl` の成果を統合） [27]。
4.  **フェーズ4**: `GoogleBigQuery.jl` における `Arrow.jl` を用いた高速読込の実装 。

この構成により、Python SDKの利便性とJuliaの実行速度を両立した、Agentが自律的に拡張可能なSDK基盤が整います。
