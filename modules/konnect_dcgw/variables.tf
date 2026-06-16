variable "name_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "aws_region" {
  description = "データプレーン / ネットワークを配置する AWS リージョン"
  type        = string
}

variable "availability_zone_ids" {
  description = "Konnect ネットワークの AZ ID (AZ-ID 形式)"
  type        = list(string)
}

variable "network_cidr_block" {
  description = "Kong 管理 Cloud Gateway ネットワークの CIDR"
  type        = string
}

variable "control_plane_geo" {
  description = "コントロールプレーンの geo (us, eu, au, me, in, sg)"
  type        = string
}

variable "gateway_version" {
  description = "データプレーンの Kong Gateway バージョン"
  type        = string
}

variable "api_access" {
  description = "データプレーン公開方法 (private / public / private+public)"
  type        = string
}

variable "base_rps" {
  description = "autopilot オートスケールの基準 RPS"
  type        = number
}

# --- Transit Gateway 接続用 (transit_gateway モジュールの出力を渡す) ---

variable "transit_gateway_id" {
  description = "ユーザー AWS アカウントの Transit Gateway ID"
  type        = string
}

variable "ram_share_arn" {
  description = "TGW を共有する RAM リソースシェアの ARN。空文字の場合 Konnect TGW を作成しない"
  type        = string
}

variable "test_vpc_cidr_blocks" {
  description = "Kong データプレーンからルートする宛先 CIDR (テスト VPC の CIDR)"
  type        = list(string)
}

variable "tags" {
  description = "タグ (Konnect 側でラベルとして使用)"
  type        = map(string)
  default     = {}
}
