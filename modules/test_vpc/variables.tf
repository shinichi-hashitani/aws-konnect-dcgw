variable "name_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "vpc_cidr" {
  description = "テスト実行用 VPC の CIDR"
  type        = string
}

variable "availability_zone_ids" {
  description = "サブネットを配置する AZ ID のリスト (AZ-ID 形式)"
  type        = list(string)
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
