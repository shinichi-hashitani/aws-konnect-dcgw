variable "enabled" {
  description = <<-EOT
    PHZ とレコードを作成するか。DCGW のデータプレーンが起動し private IP が
    確定してから有効化する (record_ips が空だとレコード作成に失敗するため)。
  EOT
  type        = bool
  default     = true
}

variable "zone_name" {
  description = "Private Hosted Zone 名 (例: gateways.konghq.com)"
  type        = string
}

variable "record_name" {
  description = "DCGW プロキシの FQDN (例: fa1a8834f3.gateways.konghq.com)"
  type        = string
}

variable "record_ips" {
  description = "FQDN を解決させる private IP のリスト (データプレーン内部 LB の IP)"
  type        = list(string)
}

variable "vpc_ids" {
  description = "PHZ を関連付ける VPC ID のリスト (app-vpc / test-vpc)"
  type        = list(string)
}

variable "ttl" {
  description = "A レコードの TTL (秒)"
  type        = number
  default     = 60
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
