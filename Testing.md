### 3. TESTING.md (テスト設計と品質保証)

Agentがテストを自動実行・検証するための設計指針です。

# Test Design & Quality Assurance

## 1. Local Development with Emulators

実リソースへの課金と遅延を避けるため、GCPエミュレータを必須とする 。

* **Tools**: `Testcontainers.jl` を使用し、Docker経由でエミュレータを起動 。


* **Environmental Toggle**: `PUBSUB_EMULATOR_HOST` 等の変数を検知し、自動で非TLS/ローカル接続へ切り替えるロジックをクライアントに含める 。

## 2. Testing Levels

* **Unit Tests**: `Mocking.jl` を用い、ネットワークIOを発生させない内部ロジックの検証 。


* **Integration Tests**: `Testcontainers.jl` を用いた BigQuery/PubSub との実機エミュレーション 。


* **Golden Tests**: APIレスポンスのスキーマ変更を検知するため、`ReferenceTests.jl` でレスポンスJSONを比較 。



## 3. CI/CD Integration

* GitHub Actions上で `Testcontainers.jl` を動作させ、マルチスレッド環境 (`JULIA_NUM_THREADS=auto`) で並列テストを実行 。


* `Aqua.jl` によるパッケージの健全性テスト（曖昧なエクスポートや依存関係の漏れをチェック） 。



## 4. Sample Test Snippetjulia

using Test, Testcontainers, GoogleCloudPubSub

# エミュレータのセットアップ例

container = Testcontainer("gcr.io/[google.com/cloudsdktool/google-cloud-cli:emulators](https://www.google.com/search?q=https://google.com/cloudsdktool/google-cloud-cli:emulators)")
with_container(container) do c
host = get_host(c)
port = get_port(c, 8432)
ENV = "$host:$port"

```
client = PubSubClient(project="test-project")
topic = create_topic(client, "test-topic")
@test exists(topic)

```

end

```

---

### 4. 実装の優先順位

Agentに対して、以下の順序でタスクをアサインすることを推奨します：

1.  **フェーズ1**: `GoogleAuth.jl` の実装（ADCとメタデータサーバ連携の完遂）。
2.  **フェーズ2**: `GoogleApiCore.jl` での `AIP-158` (ページネーション) と指数バックオフの共通化。
3.  **フェーズ3**: `GoogleCloudStorage.jl` のプロトタイプ作成（`CloudStore.jl` の成果を統合） [27]。
4.  **フェーズ4**: `GoogleBigQuery.jl` における `Arrow.jl` を用いた高速読込の実装 。

この構成により、Python SDKの利便性とJuliaの実行速度を両立した、Agentが自律的に拡張可能なSDK基盤が整います。

```