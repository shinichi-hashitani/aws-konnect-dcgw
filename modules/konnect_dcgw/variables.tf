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
  description = "TGW を共有する RAM リソースシェアの ARN (Konnect TGW リソースの引数)"
  type        = string
}

variable "tgw_attachment_enabled" {
  description = <<-EOT
    Konnect TGW アタッチメントを作成するか。RAM 共有先 Kong AWS アカウント ID が
    設定済みかどうか (plan 時に確定する値) を渡す。ram_share_arn は apply 時まで
    未確定なため count の判定には使えない。
  EOT
  type        = bool
  default     = false
}

variable "routed_cidr_blocks" {
  description = "Kong データプレーンから TGW 経由でルートする宛先 CIDR のリスト (app-vpc / test-vpc の CIDR)"
  type        = list(string)
}

variable "tags" {
  description = "タグ (Konnect 側でラベルとして使用)"
  type        = map(string)
  default     = {}
}

# --- テストアプリを公開する Gateway Service / Route ---

variable "upstream_host" {
  description = "Kong サービスの upstream ホスト名 (内部 ALB の DNS 名。scheme は含めない)"
  type        = string
}

variable "upstream_protocol" {
  description = "upstream プロトコル"
  type        = string
  default     = "http"
}

variable "upstream_port" {
  description = "upstream ポート"
  type        = number
  default     = 80
}

variable "upstream_path" {
  description = <<-EOT
    Gateway Service の path。strip_path=true 時に Route で strip 後のパスへ前置される。
    公開パス (/echo) を httpbin のエコーエンドポイント (/anything) へマップするために使用。
    null の場合は Service に path を設定しない。
  EOT
  type        = string
  default     = "/anything"
}

variable "route_paths" {
  description = "DCGW で公開するルートのパス (Kong Route エンティティの path)"
  type        = list(string)
  default     = ["/echo"]
}

variable "route_strip_path" {
  description = <<-EOT
    Route の strip_path。true の場合、マッチしたパス (/echo) を strip し、Service の
    path (/anything) を前置して upstream へ転送する (/echo -> httpbin /anything エコー)。
  EOT
  type        = bool
  default     = true
}

variable "route_protocols" {
  description = <<-EOT
    Route がマッチするプロトコル。証明書の要否とは無関係 (DCGW エッジで Konnect 管理証明書
    により TLS 終端されるため自前証明書は不要。自前証明書が要るのは Custom Domains のみ)。
    HTTPS クライアントを受けるには https を含める。
  EOT
  type        = list(string)
  default     = ["http", "https"]
}
