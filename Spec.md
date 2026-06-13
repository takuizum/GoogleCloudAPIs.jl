
### 2. SPEC.md (ライブラリ詳細仕様)

ライブラリのモジュール構成と基盤機能の設計仕様です。

# Technical Specification: Julia-GCP SDK

## 1. Modular Architecture

単一の巨大なリポジトリ（モノレポ）で管理し、以下のパッケージに分割する ：

* `GoogleApiCore.jl`: 共通のHTTP/gRPC通信ロジック、リトライ、ページネーション。
* `GoogleAuth.jl`: ADC探索、Workload Identity、Security Token Service連携。
* `GoogleCloudStorage.jl`, `GoogleBigQuery.jl`, `PubSub.jl`: サービス別パッケージ。

## 2. Authentication Logic (ADC Strategy)

`GoogleAuth.jl` は以下の順序で資格情報を探索する：

1. `GOOGLE_APPLICATION_CREDENTIALS` 環境変数。
2. `gcloud auth application-default login` で生成された既知の場所のファイル。
3. インスタンスメタデータサーバ (`http://metadata.google.internal`)。

## 3. Resilience & Retry Strategy

リトライ間隔 $T$ は以下の式で計算し、`HTTP.jl` のレイヤーとして実装する ：


$$T = \min(initial\_delay \times multiplier^{attempt}, max\_delay) + jitter$$

* `GET`, `PUT` はデフォルトでリトライ 。


* `POST` は `if-generation-match` などの事前条件がある場合のみリトライ 。

## 4. Code Generation Engine

API定義からの自動生成を基本とする ：

* **gRPC系**: `gapic-generator` のロジックを Julia に移植し、`ProtoBuf.jl` 1.0+ の高速構造体を生成 。
* **REST系**: Google Discovery Service (JSON) を読み込み、メタプログラミングで型安全なメソッドを生成 。

