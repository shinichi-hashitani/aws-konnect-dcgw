# NETWORKING — Transit Gateway 接続とルーティング

テスト VPC と Kong Dedicated Cloud Gateway (DCGW) の Cloud Gateway ネットワークを
AWS Transit Gateway (TGW) で接続する仕組みと設定手順、確認方法をまとめます。

## 1. 接続モデルの概要

DCGW のデータプレーンは **Kong 管理の AWS アカウント**内の VPC
（Cloud Gateway ネットワーク）で稼働します。ユーザーのテスト VPC とは別アカウント
のため、以下の流れで TGW を介してプライベート接続します。

```
[Kong 管理アカウント]                         [自 AWS アカウント]
 Cloud Gateway ネットワーク VPC                 テスト VPC (httpbin)
   (network_cidr_block 10.0.0.0/16)             (test_vpc_cidr_block 10.1.0.0/16)
            │                                          │
            │ ③ Kong がアタッチメント作成               │ ① TGW 作成 + VPC アタッチ
            │   (RAM 共有を受けて)                       │
            └──────────────►  Transit Gateway  ◄────────┘
                              (自アカウント所有)
                          ② TGW を RAM で Kong へ共有
```

### 役割分担

| ステップ | 実行側 | リソース / 操作 |
|---------|--------|----------------|
| Konnect: コントロールプレーン / ネットワーク / データプレーン構成 | Terraform (konnect) | `konnect_gateway_control_plane`, `konnect_cloud_gateway_network`, `konnect_cloud_gateway_configuration` |
| ① TGW 作成・テスト VPC アタッチ・ルート | Terraform (aws) | `aws_ec2_transit_gateway`, `aws_ec2_transit_gateway_vpc_attachment`, `aws_route` |
| ② TGW を Kong アカウントへ RAM 共有 | Terraform (aws) | `aws_ram_resource_share`, `aws_ram_resource_association`, `aws_ram_principal_association` |
| ③ Kong が TGW へアタッチメント作成 | Terraform (konnect) | `konnect_cloud_gateway_transit_gateway` |
| アタッチメントの承認 | AWS（自動） | TGW の `auto_accept_shared_attachments = "enable"` により自動承認 |

> **ポイント**: 「TGW を所有・共有するのはユーザー側」「アタッチメントを作成するのは
> Kong 側」という、直感と逆向きの関係になります。本構成では TGW の
> `auto_accept_shared_attachments` を有効にしているため、Kong が作成した
> アタッチメントの手動承認は不要です。

## 2. CIDR 設計

| 用途 | 変数 | 既定値 |
|------|------|--------|
| Kong 管理ネットワーク VPC | `network_cidr_block` | `10.0.0.0/16` |
| テスト VPC | `test_vpc_cidr_block` | `10.1.0.0/16` |

- 2 つの CIDR は **重複してはいけません**。
- `konnect_cloud_gateway_transit_gateway.aws_transit_gateway.cidr_blocks` には
  「Kong データプレーンがルートする宛先 = テスト VPC の CIDR」を渡します
  （本構成では `[test_vpc_cidr_block]`）。

## 3. ルーティング

### TGW レベル
`aws_ec2_transit_gateway` で以下を有効化しているため、テスト VPC アタッチメントと
Kong 側アタッチメントの双方が **デフォルト TGW ルートテーブルに自動関連付け・自動伝播**
されます。アタッチメント間の経路は自動で学習されます。

```hcl
default_route_table_association = "enable"
default_route_table_propagation = "enable"
auto_accept_shared_attachments  = "enable"
```

### テスト VPC レベル
private ルートテーブルに、Kong ネットワーク CIDR 宛のルートを TGW 向けに追加します
（`modules/transit_gateway` の `aws_route.to_kong_network`）。

```
宛先: 10.0.0.0/16 (network_cidr_block) → ターゲット: TGW
```

### Kong ネットワークレベル
Kong データプレーンからテスト VPC への戻りルートは、`konnect_cloud_gateway_transit_gateway`
に渡した `cidr_blocks`（= テスト VPC CIDR）に基づき Kong 側で構成されます。

## 4. Kong 管理 AWS アカウント ID（RAM 共有先）の確認

TGW を RAM 共有する Kong 管理アカウント ID は、**Konnect ネットワーク作成後**に
Konnect UI で確認します。

1. Konnect にログイン: <https://cloud.konghq.com/>
2. **Gateway Manager → Networks** を開く
3. 本構成で作成したネットワーク（`<project_name>-network`）の詳細を表示
4. Transit Gateway / アタッチメント設定欄に表示される **AWS アカウント ID** を確認

確認した ID を `.env` に設定して再 apply します。

```bash
# .env
export TF_VAR_kong_ram_principal_account_id="123456789012"
```

```bash
set -a; source .env; set +a
terraform apply
```

> この値が空の間は、`modules/transit_gateway` の RAM 共有リソースと
> `modules/konnect_dcgw` の `konnect_cloud_gateway_transit_gateway` が
> `count = 0` で作成されません。これにより「ネットワーク作成 → ID 確認 →
> 接続確立」の 2 段階 apply が成立します。

## 5. 2 段階 apply の流れ（再掲）

```bash
# 1 段階目: ネットワーク / データプレーン / テスト VPC / TGW を作成
terraform apply

# Konnect UI で Kong AWS アカウント ID を確認し .env に設定
export TF_VAR_kong_ram_principal_account_id="123456789012"
set -a; source .env; set +a

# 2 段階目: RAM 共有 + Konnect TGW アタッチメントを作成
terraform apply
```

接続状態の確認:

```bash
terraform output konnect_transit_gateway_state   # "ready" が正常
terraform output transit_gateway_id
terraform output ram_share_arn
```

`konnect_cloud_gateway_transit_gateway` の `state` は
`created → initializing → pending-acceptance → ready` と遷移します。
`pending-acceptance` から進まない場合は §7 を確認してください。

## 6. 接続確認

DCGW のデータプレーンからテスト VPC の httpbin（内部 ALB）へ到達できることを確認します。

1. Kong のサービス upstream に内部 ALB の DNS 名を設定:

   ```bash
   terraform output test_app_alb_dns_name
   # 例: internal-konnect-dcgw-test-alb-xxxx.ap-northeast-1.elb.amazonaws.com
   ```

2. Konnect でサービス / ルートを作成し、上記 ALB を upstream に指定
   （`http://<alb-dns-name>`、ポート 80）。

3. DCGW の公開エンドポイント経由でリクエストし、httpbin の応答を確認:

   ```bash
   curl https://<dcgw-public-endpoint>/<route-path>/get
   ```

   `/get` は httpbin がリクエスト情報を JSON で返すエンドポイントです。

### 疎通の切り分け
- ALB のターゲットグループのヘルスが `healthy` か（AWS コンソール / `aws elbv2 describe-target-health`）。
- テスト VPC private ルートテーブルに Kong CIDR → TGW のルートがあるか。
- TGW のデフォルトルートテーブルに両アタッチメントが関連付け・伝播されているか。
- ALB SG が Kong ネットワーク CIDR からの該当ポートを許可しているか。

## 7. トラブルシュート

| 症状 | 確認ポイント |
|------|------------|
| `konnect_transit_gateway_state` が `pending-acceptance` のまま | TGW の `auto_accept_shared_attachments` が `enable` か。RAM 共有 (`ram_share_arn`) が Kong アカウントに正しく関連付いているか |
| RAM 共有が Kong に届かない | `aws_ram_resource_share.allow_external_principals = true` か。`kong_ram_principal_account_id` が正しいか |
| `provider account` が見つからない (`one()` エラー) | Konnect で AWS プロバイダアカウントがリンク済みか。`konnect_cloud_gateway_provider_account_list` が AWS を返すか |
| ALB ターゲットが unhealthy | ECS タスクが起動しているか（NAT 経由でイメージ取得できているか）。ヘルスチェックパス `var.test_app_health_check_path` が 200 を返すか |
| データプレーンが Provisioning のまま | リージョンが DCGW 対応か。`gateway_version` が有効か。Konnect の課金 / プランを確認 |

## 8. 削除時の注意

`terraform destroy` 時は依存関係上、概ね以下の順で削除されます。

1. `konnect_cloud_gateway_transit_gateway`（Kong 側アタッチメント）
2. RAM 共有（`aws_ram_*`）
3. TGW VPC アタッチメント・ルート・TGW
4. ECS / ALB / VPC・Konnect ネットワーク / コントロールプレーン

- Kong 側アタッチメントが残っていると TGW を削除できません。先に
  `konnect_cloud_gateway_transit_gateway` が削除されることを確認してください。
- ネットワーク（`konnect_cloud_gateway_network`）はアタッチメントや構成が残っていると
  削除に失敗することがあります。エラー時は Konnect UI で残存リソースを確認してください。

## 9. 参考リンク

- [Dedicated Cloud Gateways (Kong Developer)](https://developer.konghq.com/dedicated-cloud-gateways/)
- [Networking in Konnect](https://developer.konghq.com/konnect-platform/network/)
- [Terraform provider for Konnect](https://github.com/Kong/terraform-provider-konnect)
- [AWS Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/what-is-transit-gateway.html)
- [AWS RAM — Transit Gateway の共有](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-transit-gateways.html#tgw-sharing)
