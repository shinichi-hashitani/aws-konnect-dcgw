# TESTING — テストの実行方法

閉域網内の **test-vpc** から ECS Fargate タスクとしてテストを実行し、
DCGW (private) 経由で app (httpbin の `/anything` エコー) への疎通・負荷を確認します。

タスクは **管理者が AWS コンソール（ECS の「タスクを実行 / Run task」）から起動**します。
パラメータ（回数・接続先など）は**環境変数で上書き**できます（タスク定義に既定値、
Run task 画面で上書き）。

| テスト | タスク定義ファミリ | 状態 |
|--------|-------------------|------|
| (1) 疎通テスト | `<project>-test-connectivity` | 実装済み |
| (2) 負荷テスト (Locust) | `<project>-test-load` | 実装済み |

> タスク定義名・クラスタ名・サブネット・SG は `terraform output` で取得できます
> （末尾「Run task に必要な値」参照）。

## 1. 疎通テスト (connectivity)

Kong (DCGW) 経由で app へ指定回数リクエストし、各レスポンスの HTTP ステータスを集計します。
200 以外を NG とし、NG が 1 件でもあればタスクは**失敗終了**（コンソールで判別可能）します。

### パラメータ（環境変数）

| 環境変数 | 既定値 | 説明 |
|----------|--------|------|
| `TARGET_URL` | `terraform` で導出（`https://<dcgw-edge>/echo`）/ `var.test_target_url` | リクエスト先 URL。**必須**（空だとエラー終了） |
| `REQUEST_COUNT` | `10`（`var.test_request_count`） | リクエスト回数 |
| `SLEEP_SECONDS` | `1` | 各リクエスト間の待機秒数 |
| `TIMEOUT_SECONDS` | `10` | 1 リクエストのタイムアウト秒数 |

> `TARGET_URL` は private DCGW のエンドポイントです。Terraform は DCGW のエッジ DNS と
> 公開パス（既定 `/echo`）から既定値を導出しますが、private 構成でエッジが解決できない
> 場合は `var.test_target_url` か Run task 画面の `TARGET_URL` で実際のエンドポイントを
> 指定してください（Konnect UI / 構築結果で確認）。

### AWS コンソールでの実行手順

1. **ECS** → クラスタ `terraform output test_ecs_cluster_name` を開く
2. **タスク** タブ → **タスクを実行 (Run task)**
3. 起動タイプ: **FARGATE**
4. タスク定義: `terraform output test_connectivity_task_family`（最新リビジョン）
5. **ネットワーキング**:
   - VPC: **test-vpc**（`terraform output test_vpc_id`）
   - サブネット: **test-vpc の private**（`terraform output test_vpc_private_subnet_ids`）
   - セキュリティグループ: `terraform output test_task_security_group_id`
   - パブリック IP: **無効 (DISABLED)**
6. （任意）**コンテナの上書き** → 環境変数で `REQUEST_COUNT` / `TARGET_URL` 等を変更
7. **作成 / 実行**

### 結果の確認

- タスクの **ログ**（CloudWatch Logs: `terraform output` の `test_task_security_group_id`
  と同じ命名規則のロググループ `/ecs/<project>-test`）で各リクエストの OK/NG と
  サマリ（`result ok=.. ng=.. total=..`）を確認します。
- タスクの **終了コード**（`0` = 全件成功、非ゼロ = NG あり）でも判別できます。

### CLI で実行する場合（参考）

```bash
CLUSTER=$(terraform output -raw test_ecs_cluster_name)
FAMILY=$(terraform output -raw test_connectivity_task_family)
SG=$(terraform output -raw test_task_security_group_id)
SUBNETS=$(terraform output -json test_vpc_private_subnet_ids | jq -r 'join(",")')

aws ecs run-task \
  --cluster "$CLUSTER" \
  --launch-type FARGATE \
  --task-definition "$FAMILY" \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"connectivity","environment":[{"name":"REQUEST_COUNT","value":"50"}]}]}'
```

## 2. 負荷テスト (load / Locust)

[Locust](https://locust.io/) を **headless** で実行し、指定した同時接続ユーザー数で
指定時間だけ Kong (DCGW) 経由の app へ継続的にリクエストします。`--processes -1` で
コンテナの全 CPU コアにワーカーを分散します。終了後、Locust が結果サマリ（RPS / レイテンシ
/ 失敗率など）をログに出力します。

### パラメータ（環境変数）

| 環境変数 | 既定値 | 説明 |
|----------|--------|------|
| `TARGET_HOST` | `terraform` で導出（`https://<dcgw-edge>`）/ `var.test_load_target_host` | Locust の `--host`（ベース URL）。**必須** |
| `TARGET_PATH` | `/echo`（`app_route_paths[0]`） | 負荷をかけるパス |
| `USERS` | `200`（`var.test_load_users`、**最大 1000**） | 同時接続ユーザー数 |
| `SPAWN_RATE` | `50` | 1 秒あたりに増やすユーザー数 |
| `RUN_TIME` | `5m`（`var.test_load_run_time`、**最長 30m 想定**） | 実行時間（Locust 形式: `5m` / `30m` / `300s`） |

> 同時接続を 1000 まで上げる場合は、タスクの CPU/メモリ（`var.load_task_cpu` /
> `var.load_task_memory`、既定 2048/4096）も必要に応じて引き上げてください。

### AWS コンソールでの実行手順

疎通テストと同じ手順で、タスク定義に **`terraform output test_load_task_family`** を選びます。
**コンテナの上書き**で `USERS` / `RUN_TIME` / `SPAWN_RATE` / `TARGET_HOST` を指定します。

1. **ECS** → クラスタ `terraform output test_ecs_cluster_name`
2. **タスクを実行 (Run task)** → 起動タイプ **FARGATE**
3. タスク定義: `terraform output test_load_task_family`
4. ネットワーキング: **test-vpc の private サブネット** / SG `terraform output test_task_security_group_id` / パブリック IP **無効**
5. （任意）環境変数で `USERS=1000` / `RUN_TIME=30m` などを指定
6. **実行**

### 結果の確認

- CloudWatch Logs（ロググループ `/ecs/<project>-test`、ストリーム接頭辞 `load`）に
  Locust の統計（リクエスト数・失敗数・RPS・レイテンシ分布・最終サマリ）が出力されます。
- 失敗が発生するとタスクは非ゼロ終了します（`--exit-code-on-error`、Locust 既定）。

### CLI で実行する場合（参考）

```bash
CLUSTER=$(terraform output -raw test_ecs_cluster_name)
FAMILY=$(terraform output -raw test_load_task_family)
SG=$(terraform output -raw test_task_security_group_id)
SUBNETS=$(terraform output -json test_vpc_private_subnet_ids | jq -r 'join(",")')

aws ecs run-task \
  --cluster "$CLUSTER" \
  --launch-type FARGATE \
  --task-definition "$FAMILY" \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"load","environment":[{"name":"USERS","value":"1000"},{"name":"RUN_TIME","value":"30m"}]}]}'
```

## Run task に必要な値（terraform output）

```bash
terraform output test_run_task_hint            # 実行手順の概要
terraform output test_ecs_cluster_name         # クラスタ名
terraform output test_connectivity_task_family # 疎通テストのタスク定義
terraform output test_load_task_family         # 負荷テストのタスク定義
terraform output test_vpc_id                   # test-vpc
terraform output test_vpc_private_subnet_ids   # サブネット
terraform output test_task_security_group_id   # SG
```
