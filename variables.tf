# =============================================================================
# 共通 / プロジェクト全体
# =============================================================================

variable "project_name" {
  description = "リソース名のプレフィックスに使う識別子"
  type        = string
  default     = "konnect-dcgw"
}

variable "aws_region" {
  description = "テスト VPC と Dedicated Cloud Gateway データプレーンを配置する AWS リージョン"
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
  description = "データプレーンの公開方法。private / public / private+public"
  type        = string
  default     = "private+public"
}

variable "base_rps" {
  description = "autopilot オートスケールの基準 RPS"
  type        = number
  default     = 100
}

variable "availability_zone_ids" {
  description = <<-EOT
    Konnect ネットワークおよびテスト VPC で使う AZ ID (AZ 名ではなく AZ-ID 形式)。
    ap-northeast-1 の例: ["apne1-az1", "apne1-az4"] (apne1-az3 は新規割当不可の場合あり)
  EOT
  type        = list(string)
  default     = ["apne1-az1", "apne1-az4"]
}

# =============================================================================
# ネットワーク CIDR (相互に重複しないこと)
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

variable "test_vpc_cidr_block" {
  description = "テスト用 (httpbin) VPC の CIDR。サブネットは /26 で切り出すため 2 AZ では /24 が目安"
  type        = string
  default     = "10.1.0.0/24"
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
# テスト用アプリ (httpbin / ECS Fargate)
# =============================================================================

variable "test_app_image" {
  description = "テスト API のコンテナイメージ。後で差し替え可能"
  type        = string
  default     = "kennethreitz/httpbin:latest"
}

variable "test_app_container_port" {
  description = "テスト API コンテナが listen するポート"
  type        = number
  default     = 80
}

variable "test_app_health_check_path" {
  description = "ALB ターゲットグループのヘルスチェックパス"
  type        = string
  default     = "/get"
}

variable "test_app_route_paths" {
  description = "DCGW で httpbin を公開する Kong Route のパス"
  type        = list(string)
  default     = ["/httpbin"]
}

variable "test_app_desired_count" {
  description = "ECS サービスの希望タスク数"
  type        = number
  default     = 1
}

variable "test_app_cpu" {
  description = "Fargate タスクの CPU ユニット"
  type        = number
  default     = 256
}

variable "test_app_memory" {
  description = "Fargate タスクのメモリ (MiB)"
  type        = number
  default     = 512
}
