
### 1. agent.md (エージェント向け指示書)

このファイルは、Agentがプロジェクトの全体像、コーディング規約、および技術的優先順位を理解するためのものです。

# Agent Instructions: Julia Google Cloud SDK Development

## Role & Goal

あなたはJulia言語のエキスパート・ソフトウェアエンジニアです。
目標は、Python版Google Cloud SDKと同等の機能、信頼性、保守性を備えた、JuliaネイティブなGCPクライアントライブラリ群を構築することです。

## Core Principles

1. **Performance First**: `Arrow.jl`を活用したゼロコピー転送をデフォルトとする 。


2. **Type Safety**: Juliaの強力な型システムと多重ディスパッチを最大限活用し、コンパイル時最適化が可能な設計を行う 。


3. **Idiomatic Julia**: Pythonの逐次移植ではなく、`Task`と`Channel`による非同期処理、`iterate`によるページネーションなど、Juliaらしい記述を追求する 。


4. **Cloud Native Security**: 秘密鍵ファイルの直接参照を避け、ADC (Application Default Credentials) や Workload Identity を優先実装する 。



## Technology Stack

* **Communication**: `HTTP.jl` (REST/JSON), `gRPCClient.jl` (gRPC), `ProtoBuf.jl` 。


* **Serialization**: `JSON3.jl`, `StructTypes.jl`, `Arrow.jl` 。


* **Auth**: `CloudBase.jl` を基盤とした認証認可プロトコルの統合 。


* **Retry**: 指数バックオフとジッターを伴うべき等性ベースのリトライ 。



## Design Standards (AIP Compliance)

GoogleのAPI設計指針 (API Improvement Proposals) に厳格に従ってください：

* **AIP-151 (LRO)**: 長時間実行操作は `Operation` オブジェクトを Julia の `Task` に抽象化する 。


* **AIP-158 (Pagination)**: `page_token` 管理を隠蔽し、`Base.iterate` を実装する 。
* **AIP-193 (Errors)**: `google.rpc.Status` に基づく共通例外クラスの構築 。



## Development Workflow

* 新しい機能の実装前に、必ず `test/` 内にエミュレータ（Testcontainers.jl）を利用したテストケースを作成すること 。


* `Documenter.jl` 用のドキュメントをコードと同時に作成すること。

---

### 2. SPEC.md (ライブラリ詳細仕様)

ライブラリのモジュール構成と基盤機能の設計仕様です。

# Technical Specification: Julia-GCP SDK

## 1. Modular Architecture

単一の巨大なリポジトリ（モノレポ）で管理し、以下のパッケージに分割する ：

* `GoogleApiCore.jl`: 共通のHTTP/gRPC通信ロジック、リトライ、ページネーション。
* `GoogleAuth.jl`: ADC探索、Workload Identity、Security Token Service連携。
* `GoogleCloudStorage.jl`, `BigQuery.jl`, `PubSub.jl`: サービス別パッケージ。

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

