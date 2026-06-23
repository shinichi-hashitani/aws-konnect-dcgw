# PREREQUISITES — 事前準備・必要権限・テスト環境

このドキュメントは、本リポジトリを実行する前に必要なツール・アカウント・権限と、
app-vpc（httpbin）/ test-vpc（テストクライアント）の構成を説明します。本構成は
閉塞ネットワーク化のため DCGW を `api_access = private` で構成します。

## 1. 必要なツール

| ツール | バージョン | 用途 |
|--------|-----------|------|
| Terraform | >= 1.5 | インフラ構築 |
| AWS CLI | >= 2.x（必須） | IAM Identity Center (SSO) ログイン・認証確認・接続検証 |
| Git | 任意 | リポジトリ管理 |

> AWS CLI v2 は SSO ログイン (`aws sso login`) に必要です。

## 2. アカウント

### AWS アカウント
- app-vpc / test-vpc、ECS Fargate、Transit Gateway、RAM 共有を作成します。
- DCGW のデータプレーンは Kong 管理の別 AWS アカウントに作成されるため、
  ユーザー側アカウントには **作成されません**（TGW で接続するのみ）。
- アクセスは **IAM Identity Center (AWS SSO) で定義したユーザー**で行います。
  対象アカウントへのアクセス権を持つ permission set（後述の IAM 権限を満たすもの）が
  割り当てられている必要があります。アクセスキーの常用は不要です。

### Kong Konnect アカウント
- Personal Access Token (PAT) を発行します。
  - 取得: <https://cloud.konghq.com/> → アカウントメニュー → **Personal Access Tokens**
  - `.env` の `KONNECT_TOKEN` に設定します（konnect provider が自動的に読み込みます）。
- 対象組織で **Dedicated Cloud Gateways** が利用可能なプランであること。
- Konnect とクラウドプロバイダ (AWS) のリンクが済んでいること
  （`konnect_cloud_gateway_provider_account_list` データソースで AWS プロバイダ
  アカウントが 1 件以上返る必要があります）。

## 3. 認証情報の渡し方

### 3.1 AWS: IAM Identity Center (AWS SSO)

アクセスキーではなく、IAM Identity Center のユーザーで SSO ログインします。

```bash
# 初回のみ: SSO プロファイルを対話設定
aws configure sso
#   SSO start URL     : https://<your-portal>.awsapps.com/start
#   SSO region        : <Identity Center のリージョン>
#   アカウント / ロール : 対象を選択
#   CLI default region : ap-northeast-1
#   profile name      : 例) konnect-dcgw

# 作業のたびにログイン (SSO トークンは数時間で失効するため都度実行)
aws sso login --profile konnect-dcgw

# 認証確認
aws sts get-caller-identity
```

`~/.aws/config` には次のようなプロファイルが作成されます（参考）:

```ini
[profile konnect-dcgw]
sso_session = my-sso
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = ap-northeast-1

[sso-session my-sso]
sso_start_url = https://<your-portal>.awsapps.com/start
sso_region = <Identity Center のリージョン>
sso_registration_scopes = sso:account:access
```

Terraform / AWS プロバイダは環境変数 `AWS_PROFILE` でこのプロファイルを参照し、
`aws sso login` で取得した SSO キャッシュを自動的に利用します。

### 3.2 環境変数 (`.env`)

その他は `.env`（`.env.example` をコピー）で環境変数として渡します。

```bash
cp .env.example .env
# 値を設定
set -a; source .env; set +a
```

| 変数 | 説明 |
|------|------|
| `AWS_PROFILE` | 使用する IAM Identity Center (SSO) プロファイル名（`aws configure sso` で付けた名前） |
| `AWS_REGION` | デプロイ先リージョン（`var.aws_region` と一致させる） |
| `KONNECT_TOKEN` | Konnect Personal Access Token |
| `KONNECT_SERVER_URL` | Konnect API エンドポイント（geo 別） |
| `TF_VAR_kong_ram_principal_account_id` | RAM 共有先の Kong 管理 AWS アカウント ID（後述） |

> 秘匿情報を `terraform.tfvars` に書かないでください。`.env`（環境変数）経由を推奨します。
> SSO 方式ではアクセスキー／シークレットを `.env` に保存する必要はありません。

## 4. 必要な AWS IAM 権限

作業者の IAM プリンシパルには、最低限以下の操作権限が必要です。検証環境では
管理者相当でも構いませんが、最小権限で運用する場合の目安を示します。

### VPC / ネットワーキング
- `ec2:*Vpc*`, `ec2:*Subnet*`, `ec2:*RouteTable*`, `ec2:*Route`, `ec2:*InternetGateway*`
- `ec2:*NatGateway*`, `ec2:*Address*` (EIP), `ec2:*SecurityGroup*`
- `ec2:Describe*`

### Transit Gateway
- `ec2:CreateTransitGateway`, `ec2:DeleteTransitGateway`, `ec2:DescribeTransitGateways`
- `ec2:CreateTransitGatewayVpcAttachment`, `ec2:DeleteTransitGatewayVpcAttachment`,
  `ec2:DescribeTransitGatewayVpcAttachments`, `ec2:AcceptTransitGatewayVpcAttachment`
- `ec2:*TransitGatewayRouteTable*`, `ec2:*TransitGatewayAttachment*` (Describe 含む)

### AWS RAM（TGW を Kong アカウントへ共有）
- `ram:CreateResourceShare`, `ram:DeleteResourceShare`, `ram:UpdateResourceShare`
- `ram:AssociateResourceShare`, `ram:DisassociateResourceShare`
- `ram:GetResourceShares`, `ram:ListPrincipals`, `ram:ListResources`
- `ram:EnableSharingWithAwsOrganization`（外部プリンシパル共有を使うため `allow_external_principals = true` を設定済み。Organizations を使う場合のみ必要）

### ECS / ALB / IAM / ログ（テストアプリ）
- `ecs:*`（クラスタ・タスク定義・サービス）
- `elasticloadbalancing:*`（ALB・ターゲットグループ・リスナー）
- `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`,
  `iam:PassRole`, `iam:GetRole`, `iam:TagRole`
- `logs:CreateLogGroup`, `logs:DeleteLogGroup`, `logs:PutRetentionPolicy`, `logs:DescribeLogGroups`

> **Transit Gateway の RAM 共有に関する権限がポイントです。** TGW を Kong 管理
> アカウントへ RAM 共有するには上記 `ram:*` と `ec2:*TransitGateway*` 権限が必要です。
> Kong 側はこの共有を受けて TGW へアタッチメントを作成します。詳細は
> [NETWORKING.md](./NETWORKING.md) を参照してください。

## 5. Kong Gateway（データプレーン）バージョンの指定

DCGW のデータプレーンとして動作する Kong Gateway のバージョンは `var.gateway_version`
で指定します（既定 `3.14`）。

```hcl
# terraform.tfvars
gateway_version = "3.14"
```

または環境変数で渡すこともできます:

```bash
# .env など
export TF_VAR_gateway_version="3.14"
```

### 利用可能なバージョンの確認

指定可能なバージョンは Konnect の **availability** エンドポイント（**グローバル**
エンドポイント `https://global.api.konghq.com`）で確認します。地域別エンドポイント
（`https://us.api.konghq.com` 等）は Cloud Gateways API では 404 になる点に注意してください。

```bash
curl -s https://global.api.konghq.com/v2/cloud-gateways/availability.json \
  -H "Authorization: Bearer $KONNECT_TOKEN" | jq '.versions'
```

> 返却される `versions` のうち最新を指定するのが基本です（執筆時点の例:
> `3.14 / 3.13 / 3.12 / 3.11 / 3.10 / 3.4`）。利用可能なバージョンは随時更新されるため、
> 上記コマンドで都度確認してください。

### バージョン変更の反映

`gateway_version` を変更して `terraform apply` すると、`konnect_cloud_gateway_configuration`
が更新され、データプレーンが指定バージョンへ更新されます。

## 6. app-vpc / test-vpc について（閉塞構成）

本構成は閉塞ネットワーク化のため、DCGW を `api_access = private` で構成し、アプリを置く
**app-vpc** と、閉域網内からテストを実行する **test-vpc** の 2 つの VPC を用意します。
両 VPC は TGW 経由で Kong 網（private DCGW）に接続します。

### app-vpc — `modules/app_vpc`（httpbin を配置）

- **VPC** (`var.app_vpc_cidr_block`、既定 `10.1.0.0/24`)
- **サブネット**: `var.availability_zone_ids` の各 AZ に public / private を 1 つずつ（各 /26）
  - public: NAT Gateway 配置・IGW 経由の egress
  - private: ECS タスクと内部 ALB を配置
- **NAT Gateway × 1**: private サブネットからの egress（コンテナイメージ取得用）
- **内部 ALB**: `internal = true`。Kong データプレーンから TGW 経由でアクセスされる
- **ECS Fargate サービス**: `var.app_image`（既定 `kennethreitz/httpbin:latest`）を
  ポート `var.app_container_port`（既定 80）で起動
- **公開ルート**: DCGW で `var.app_route_paths`（既定 `/echo`）を公開。`strip_path = true`
  と Service path `var.app_upstream_path`（既定 `/anything`）により **`/echo` → httpbin の
  `/anything`** へマップ。`/anything` は受信リクエストのヘッダー・メソッド・ボディ等を
  そのまま JSON で返す **エコーエンドポイント**で、DCGW 通過時のヘッダー伝播確認に使う
- **セキュリティグループ**:
  - ALB SG: `var.network_cidr_block`（Kong 網）と app-vpc CIDR から該当ポートを許可
  - Task SG: ALB SG からのみ該当ポートを許可
- **CloudWatch Logs**: コンテナログ（`/ecs/<prefix>-app`、保持 14 日）

#### httpbin の差し替え
将来 httpbin から別 API へ変更する場合は、`var.app_image` /
`var.app_container_port` / `var.app_health_check_path` を変更して
`terraform apply` するだけです。httpbin のヘルスチェックは既定で `/get`（200 応答）を使用します。

### test-vpc — `modules/test_vpc`（テスト実行クライアント用）

- **VPC** (`var.test_vpc_cidr_block`、既定 `10.2.0.0/24`)
- **サブネット**: 各 AZ に public / private を 1 つずつ（各 /26）
- **NAT Gateway × 1** / **IGW**: クライアントのツール取得などの egress 用
- private ルートテーブルに Kong 網 CIDR 向け TGW ルートを保持（DCGW へ到達するため）

> **現状はネットワークのみ**です。テストを実行するクライアント本体（EC2 / ECS など）、
> private DCGW へのリクエスト方法、テストケースは**次ステップで決定・実装**します。

### アクセス経路（閉塞）
test-vpc のクライアント → TGW → Kong 網（**private** DCGW）→ TGW → app-vpc の内部 ALB →
ECS Fargate (httpbin)。DCGW は外部公開エンドポイントを持たないため、インターネットから
直接アクセスはできません。Kong のサービス upstream には app-vpc 内部 ALB の DNS 名
（`terraform output app_alb_dns_name`）を指定します。

## 7. リージョン・AZ に関する注意

- 既定リージョンは `ap-northeast-1`（東京）です。**対象リージョンで DCGW が
  サポートされているか必ず確認してください。** 非対応の場合は `aws_region` と
  `availability_zone_ids` を変更します（例: `us-east-2` / `["use2-az1","use2-az2"]`）。
- `availability_zone_ids` は **AZ-ID 形式**（`apne1-az1` など）で指定します。AZ 名
  （`ap-northeast-1a`）ではない点に注意してください。
- `control_plane_geo` と `konnect_server_url` の geo は一致させてください
  （既定は `us` / `https://us.api.konghq.com`）。コントロールプレーンの geo は
  データプレーンのリージョンとは独立です。
