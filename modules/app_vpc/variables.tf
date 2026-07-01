variable "name_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "aws_region" {
  description = "AWS リージョン"
  type        = string
}

variable "vpc_cidr" {
  description = "アプリ (httpbin) VPC の CIDR"
  type        = string
}

variable "availability_zone_ids" {
  description = "サブネットを配置する AZ ID のリスト (AZ-ID 形式)"
  type        = list(string)
}

variable "allowed_ingress_cidrs" {
  description = "アプリ ALB へのアクセスを許可する CIDR (Kong ネットワーク CIDR など)"
  type        = list(string)
}

variable "app_image" {
  description = "アプリ (httpbin) のコンテナイメージ"
  type        = string
}

variable "container_port" {
  description = "コンテナの listen ポート"
  type        = number
}

variable "health_check_path" {
  description = "ALB ヘルスチェックパス"
  type        = string
}

variable "desired_count" {
  description = "ECS サービスの希望タスク数"
  type        = number
}

variable "task_cpu" {
  description = "Fargate タスク CPU"
  type        = number
}

variable "task_memory" {
  description = "Fargate タスク メモリ (MiB)"
  type        = number
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
