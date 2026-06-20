# Kong Konnect Dedicated Cloud Gateway on AWS (Terraform)

[Kong Konnect Dedicated Cloud Gateway (DCGW)](https://developer.konghq.com/dedicated-cloud-gateways/) を
[Terraform provider for Konnect](https://github.com/Kong/terraform-provider-konnect) で構築し、
AWS Transit Gateway 経由でテスト用 API (httpbin) を配置した VPC と接続する環境一式です。

## 全体構成

```
                 ┌──────────────────────────────┐
                 │  Kong (Konnect 管理 AWS アカウント) │
                 │  ┌────────────────────────┐    │
                 │  │ Cloud Gateway Network   │    │
                 │  │ (Kong 管理 VPC)         │    │
                 │  │  Dedicated データプレーン │    │
                 │  └───────────┬────────────┘    │
                 └──────────────┼─────────────────┘
                                │ TGW アタッチメント
                                │ (RAM 共有 + 自動承認)
        ┌───────────────────────┴───────────────────────┐
        │           Transit Gateway (自 AWS アカウント)     │
        └───────────────────────┬───────────────────────┘
                                │ VPC アタッチメント
                 ┌──────────────┴─────────────────┐
                 │  テスト VPC (10.1.0.0/24)        │
                 │  ┌──────────────────────────┐   │
                 │  │ 内部 ALB → ECS Fargate     │   │
                 │  │ (httpbin :80)             │   │
                 │  └──────────────────────────┘   │
                 └────────────────────────────────┘
```

- **Konnect 側 (`modules/konnect_dcgw`)**: コントロールプレーン、Cloud Gateway ネットワーク、
  データプレーン構成、Transit Gateway アタッチメントを Terraform provider for Konnect で管理。
- **テスト VPC (`modules/test_app_vpc`)**: httpbin を ECS Fargate で起動し内部 ALB の背後に配置。
  イメージは `var.test_app_image` で差し替え可能。
- **Transit Gateway (`modules/transit_gateway`)**: 自 AWS アカウントに TGW を作成し、テスト VPC を
  アタッチ。TGW を AWS RAM で Kong 管理アカウントへ共有し、Kong 側アタッチメントを自動承認。

関連ドキュメント:
- [PREREQUISITES.md](./PREREQUISITES.md) — 事前準備、必要権限、テスト VPC / アプリの説明。
- [NETWORKING.md](./NETWORKING.md) — TGW / RAM / ルーティングの詳細と接続確認手順。

## ディレクトリ構成

```
.
├── README.md / PREREQUISITES.md / NETWORKING.md
├── .env.example                 # 認証情報のテンプレート (コピーして .env を作成)
├── versions.tf                  # Terraform / provider バージョン制約・backend
├── providers.tf                 # aws / konnect プロバイダ設定
├── variables.tf                 # 入力変数
├── terraform.tfvars.example     # 変数の上書き例
├── main.tf                      # モジュール結線
├── outputs.tf                   # 出力
└── modules/
    ├── konnect_dcgw/            # Konnect: CP / ネットワーク / 構成 / TGW
    ├── test_app_vpc/            # テスト VPC + ECS Fargate (httpbin) + 内部 ALB
    └── transit_gateway/         # TGW + RAM 共有 + VPC アタッチ + ルート
```

## 必要なもの

- Terraform >= 1.5
- AWS アカウントと認証情報 (詳細は [PREREQUISITES.md](./PREREQUISITES.md))
- Kong Konnect アカウントと Personal Access Token
- 対象 AWS リージョンでの DCGW 利用可否を確認（既定: `ap-northeast-1`。
  利用不可の場合は `aws_region` / `availability_zone_ids` を変更）

## セットアップ手順

### 1. 認証情報の設定

AWS は **IAM Identity Center (AWS SSO)** のプロファイルを使用します。

```bash
# 初回のみ: SSO プロファイルを設定 (start URL / リージョン / アカウント・ロール / プロファイル名)
aws configure sso            # 例: profile name = konnect-dcgw

cp .env.example .env
# .env を編集: AWS_PROFILE に上で付けたプロファイル名、Konnect の KONNECT_TOKEN 等を設定
set -a; source .env; set +a

# 作業のたびにログイン (トークン期限切れ時も再実行)
aws sso login --profile "$AWS_PROFILE"

# 認証確認 (アカウント ID が返れば OK)
aws sts get-caller-identity
```

必要に応じて変数を上書き:

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集 (任意)
```

### 2. 初期化

```bash
terraform init
```

### 3. 1 段階目の apply（ネットワーク作成まで）

TGW を RAM 共有する Kong 管理 AWS アカウント ID は、Konnect ネットワーク作成後に
Konnect UI で確認します。初回はその ID を空のまま apply します（RAM 共有と
Konnect TGW アタッチメントは自動的にスキップされます）。

```bash
terraform apply
```

> `kong_ram_principal_account_id` が空のため、テスト VPC・TGW・Konnect の
> ネットワーク/データプレーンまでが作成されます。

### 4. Kong AWS アカウント ID を確認して設定

Konnect UI で確認します（手順は [NETWORKING.md](./NETWORKING.md) 参照）:

```
Konnect → Gateway Manager → Networks → 作成したネットワーク → 詳細
```

確認した AWS アカウント ID を `.env` に設定し直します:

```bash
# .env
export TF_VAR_kong_ram_principal_account_id="123456789012"
```

```bash
set -a; source .env; set +a
```

### 5. 2 段階目の apply（TGW 接続を確立）

```bash
# SSO トークンが失効していれば再ログイン
aws sso login --profile "$AWS_PROFILE"

terraform apply
```

RAM 共有と `konnect_cloud_gateway_transit_gateway` が作成され、Kong 側からの
アタッチメントが自動承認されます。`terraform output konnect_transit_gateway_state`
が `ready` になれば接続完了です。

### 6. 接続確認

接続確認とトラブルシュートは [NETWORKING.md](./NETWORKING.md) を参照してください。
Kong のルート/サービスを設定する際は、upstream に内部 ALB の DNS 名を指定します:

```bash
terraform output test_app_alb_dns_name
```

## クリーンアップ

```bash
terraform destroy
```

> TGW アタッチメントや RAM 共有が残っていると削除が滞ることがあります。
> 詳細は [NETWORKING.md](./NETWORKING.md) の「削除時の注意」を参照してください。

## 注意事項

- 本構成はローカル state を使用します。チーム運用では `versions.tf` の S3 backend
  を有効化してください。
- DCGW のデータプレーン稼働には Konnect の課金が発生します。検証後は `destroy` を推奨します。
- 秘匿情報 (`.env`, `terraform.tfvars`, `*.tfstate`) は `.gitignore` 済みです。コミットしないでください。
