# =============================================================================
# 共通 / プロジェクト全体
# =============================================================================

variable "project_name" {
  description = "リソース名のプレフィックスに使う識別子"
  type        = string
  default     = "konnect-dcgw"
}

variable "aws_region" {
  description = "VPC と Dedicated Cloud Gateway データプレーンを配置する AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "tags" {
  description = "全リソースに付与する共通タグ"
  type        = map(string)
  default = {
    Project   = "konnect-dcgw"
    ManagedBy = "terraform"
  }
}

# =============================================================================
# Kong Konnect
# =============================================================================

variable "konnect_server_url" {
  description = "Konnect の geo に対応する API エンドポイント (.env の KONNECT_SERVER_URL と一致させる)"
  type        = string
  default     = "https://us.api.konghq.com"
}

variable "konnect_personal_access_token" {
  description = "Konnect Personal Access Token。null の場合は環境変数 KONNECT_TOKEN を使用"
  type        = string
  default     = null
  sensitive   = true
}

variable "control_plane_geo" {
  description = "コントロールプレーンの geo。許可値: us, eu, au, me, in, sg (konnect_server_url の geo と一致させる)"
  type        = string
  default     = "us"

  validation {
    condition     = contains(["us", "eu", "au", "me", "in", "sg"], var.control_plane_geo)
    error_message = "control_plane_geo は us, eu, au, me, in, sg のいずれかである必要があります。"
  }
}

variable "gateway_version" {
  description = "Dedicated Cloud Gateway のデータプレーン Kong Gateway バージョン (利用可能版は availability.json で確認)"
  type        = string
  default     = "3.14"
}

variable "api_access" {
  description = <<-EOT
    データプレーンの公開方法。private / public / private+public。
    本構成は閉塞ネットワーク化のため既定を private とし、外部公開エンドポイント
    (Public Edge DNS) を持たせない。テストは閉域網内の test-vpc から実行する。
  EOT
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public", "private+public"], var.api_access)
    error_message = "api_access は private, public, private+public のいずれかである必要があります。"
  }
}

variable "base_rps" {
  description = "autopilot オートスケールの基準 RPS"
  type        = number
  default     = 100
}

variable "availability_zone_ids" {
  description = <<-EOT
    Konnect ネットワークおよび各 VPC で使う AZ ID (AZ 名ではなく AZ-ID 形式)。
    ap-northeast-1 の例: ["apne1-az1", "apne1-az4"] (apne1-az3 は新規割当不可の場合あり)
  EOT
  type        = list(string)
  default     = ["apne1-az1", "apne1-az4"]
}

# =============================================================================
# ネットワーク CIDR (相互に重複しないこと)
#   Kong network : Kong 管理 Cloud Gateway VPC
#   app-vpc      : httpbin (ECS Fargate / 内部 ALB) を配置
#   test-vpc     : 閉域網内からテストを実行するクライアントを配置
# =============================================================================

variable "network_cidr_block" {
  description = "Kong 管理の Cloud Gateway ネットワーク VPC の CIDR。Kong の制約により prefix は /16〜/23 (2 AZ は最小 /23)"
  type        = string
  default     = "10.0.0.0/23"

  validation {
    condition     = can(cidrhost(var.network_cidr_block, 0)) && tonumber(split("/", var.network_cidr_block)[1]) >= 16 && tonumber(split("/", var.network_cidr_block)[1]) <= 23
    error_message = "network_cidr_block の prefix は /16〜/23 である必要があります (Kong Cloud Gateway ネットワークの制約)。"
  }
}

variable "app_vpc_cidr_block" {
  description = "アプリ (httpbin) VPC の CIDR。サブネットは /26 で切り出すため 2 AZ では /24 が目安"
  type        = string
  default     = "10.1.0.0/24"
}

variable "test_vpc_cidr_block" {
  description = "テスト実行用 VPC の CIDR。サブネットは /26 で切り出すため 2 AZ では /24 が目安"
  type        = string
  default     = "10.2.0.0/24"
}

# =============================================================================
# Transit Gateway / RAM
# =============================================================================

variable "kong_ram_principal_account_id" {
  description = <<-EOT
    Transit Gateway を RAM 共有する Kong 管理 AWS アカウント ID。
    Konnect ネットワーク作成後に Konnect UI (Gateway Manager -> Networks) で確認する。
    確認できるまでは空文字のままにし、RAM 共有 / Konnect TGW の作成をスキップできる。
  EOT
  type        = string
  default     = ""
}

variable "amazon_side_asn" {
  description = "Transit Gateway の Amazon 側 ASN"
  type        = number
  default     = 64512
}

# =============================================================================
# アプリ (httpbin / ECS Fargate) — app-vpc に配置
# =============================================================================

variable "app_image" {
  description = "アプリのコンテナイメージ。後で差し替え可能"
  type        = string
  default     = "kennethreitz/httpbin:latest"
}

variable "app_container_port" {
  description = "アプリコンテナが listen するポート"
  type        = number
  default     = 80
}

variable "app_health_check_path" {
  description = "ALB ターゲットグループのヘルスチェックパス"
  type        = string
  default     = "/get"
}

variable "app_route_paths" {
  description = "DCGW で公開する Kong Route のパス (公開パス)。用途はエコーのため既定 /echo"
  type        = list(string)
  default     = ["/echo"]
}

variable "app_upstream_path" {
  description = "Gateway Service の path。公開パス (/echo) を httpbin のエコーエンドポイント (/anything) へマップする"
  type        = string
  default     = "/anything"
}

variable "app_route_strip_path" {
  description = "Route の strip_path。true で公開パス (/echo) を strip し Service path (/anything) を前置して転送 (/echo -> httpbin /anything)"
  type        = bool
  default     = true
}

variable "app_route_protocols" {
  description = "Route がマッチするプロトコル。https を含めても自前証明書は不要 (DCGW エッジが TLS 終端)"
  type        = list(string)
  default     = ["http", "https"]
}

variable "app_desired_count" {
  description = "ECS サービスの希望タスク数"
  type        = number
  default     = 1
}

variable "app_cpu" {
  description = "Fargate タスクの CPU ユニット"
  type        = number
  default     = 256
}

variable "app_memory" {
  description = "Fargate タスクのメモリ (MiB)"
  type        = number
  default     = 512
}

# =============================================================================
# テスト実行タスク (test-vpc / ECS Fargate)
# =============================================================================

variable "test_client_image" {
  description = "テストクライアントのコンテナイメージ (curl 同梱)"
  type        = string
  default     = "curlimages/curl:latest"
}

variable "test_target_url" {
  description = <<-EOT
    テストの接続先 URL (例: https://<dcgw-edge>/echo)。
    空の場合は DCGW エッジ DNS + 公開パス (app_route_paths[0]) から自動導出する。
    private 構成でエッジが解決できない等の場合は、この変数か Run task UI の環境変数
    TARGET_URL で明示指定する。
  EOT
  type        = string
  default     = ""
}

variable "test_request_count" {
  description = "疎通テストのリクエスト回数 (タスク定義の既定値。Run task UI で REQUEST_COUNT 上書き可)"
  type        = number
  default     = 10
}

# --- 負荷テスト (Locust) ---

variable "test_load_target_host" {
  description = "負荷テストのベース URL (例: https://<dcgw-edge>)。空なら DCGW エッジ DNS から自動導出。Run task UI で TARGET_HOST 上書き可"
  type        = string
  default     = ""
}

variable "test_load_users" {
  description = "負荷テストの同時接続ユーザー数 (数百〜最大 1000)。Run task UI で USERS 上書き可"
  type        = number
  default     = 200

  validation {
    condition     = var.test_load_users >= 1 && var.test_load_users <= 1000
    error_message = "test_load_users は 1〜1000 の範囲で指定してください。"
  }
}

variable "test_load_spawn_rate" {
  description = "負荷テストで 1 秒あたりに増やすユーザー数。Run task UI で SPAWN_RATE 上書き可"
  type        = number
  default     = 50
}

variable "test_load_run_time" {
  description = "負荷テストの実行時間 (Locust 形式: 5m / 30m / 300s など。5分〜最長30分想定)。Run task UI で RUN_TIME 上書き可"
  type        = string
  default     = "5m"
}

# --- DCGW プロキシ用 Private DNS (Route53 PHZ) ---

variable "enable_gateway_private_dns" {
  description = <<-EOT
    DCGW プロキシ FQDN を private IP へ解決する Route53 Private Hosted Zone を作成するか。
    データプレーンが起動し private IP が確定してから有効化する (IP が空だとレコード
    作成に失敗するため)。既定 true。まっさらな初回 apply 等で DP 未起動の場合は
    false にし、DP 起動後に true で再 apply する。
  EOT
  type        = bool
  default     = true
}

variable "gateway_dns_zone_name" {
  description = "DCGW プロキシ FQDN 解決用の Private Hosted Zone 名 (DCGW エッジのドメイン)"
  type        = string
  default     = "gateways.konghq.com"
}
