variable "name_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "amazon_side_asn" {
  description = "Transit Gateway の Amazon 側 ASN"
  type        = number
}

variable "vpc_attachments" {
  description = <<-EOT
    TGW にアタッチする VPC のマップ。キーは識別子 (例: app / test)。
      vpc_id          : アタッチ対象 VPC の ID
      subnet_ids      : アタッチメントを配置するサブネット ID (AZ ごとに 1 つ)
      route_table_ids : Kong ネットワーク CIDR 向けルートを追加するルートテーブル ID
  EOT
  type = map(object({
    vpc_id          = string
    subnet_ids      = list(string)
    route_table_ids = list(string)
  }))
}

variable "kong_network_cidr" {
  description = "Kong 管理 Cloud Gateway ネットワークの CIDR (テスト VPC からのルート宛先)"
  type        = string
}

variable "kong_ram_principal_account_id" {
  description = "TGW を RAM 共有する Kong 管理 AWS アカウント ID。空文字の場合 RAM 共有を作成しない"
  type        = string
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
