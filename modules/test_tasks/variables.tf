variable "name_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "aws_region" {
  description = "AWS リージョン (ログ設定用)"
  type        = string
}

variable "vpc_id" {
  description = "テストタスクを配置する test-vpc の ID (セキュリティグループ作成用)"
  type        = string
}

variable "image" {
  description = "テストクライアントのコンテナイメージ (curl 同梱)"
  type        = string
  default     = "curlimages/curl:latest"
}

variable "target_url" {
  description = <<-EOT
    疎通テストのリクエスト先 URL (例: https://<dcgw-edge>/echo)。
    タスク定義の既定値。ECS「タスクを実行」UI で環境変数 TARGET_URL を上書き可能。
    空の場合、タスク実行時に TARGET_URL が未設定だとスクリプトはエラー終了する。
  EOT
  type        = string
  default     = ""
}

variable "request_count" {
  description = "疎通テストのリクエスト回数 (環境変数 REQUEST_COUNT の既定値)"
  type        = number
  default     = 10
}

variable "sleep_seconds" {
  description = "各リクエスト間の待機秒数 (環境変数 SLEEP_SECONDS の既定値)"
  type        = number
  default     = 1
}

variable "timeout_seconds" {
  description = "1 リクエストあたりのタイムアウト秒数 (環境変数 TIMEOUT_SECONDS の既定値)"
  type        = number
  default     = 10
}

variable "task_cpu" {
  description = "Fargate タスクの CPU ユニット"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate タスクのメモリ (MiB)"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch Logs の保持日数"
  type        = number
  default     = 14
}

# --- (2) 負荷テスト (Locust) ---

variable "load_image" {
  description = "負荷テストのコンテナイメージ (Locust)"
  type        = string
  default     = "locustio/locust:latest"
}

variable "load_target_host" {
  description = "Locust の --host (ベース URL。例: https://<dcgw-edge>)。Run task UI で TARGET_HOST 上書き可"
  type        = string
  default     = ""
}

variable "load_target_path" {
  description = "負荷をかけるパス (公開パス。例: /echo)。Run task UI で TARGET_PATH 上書き可"
  type        = string
  default     = "/echo"
}

variable "load_users" {
  description = "同時接続ユーザー数 (環境変数 USERS の既定値。数百〜最大 1000 を想定)"
  type        = number
  default     = 200

  validation {
    condition     = var.load_users >= 1 && var.load_users <= 1000
    error_message = "load_users は 1〜1000 の範囲で指定してください。"
  }
}

variable "load_spawn_rate" {
  description = "1 秒あたりに増やすユーザー数 (環境変数 SPAWN_RATE の既定値)"
  type        = number
  default     = 50
}

variable "load_run_time" {
  description = "実行時間 (環境変数 RUN_TIME の既定値。Locust 形式: 例 5m / 30m / 300s)。5分〜最長30分を想定"
  type        = string
  default     = "5m"
}

variable "load_task_cpu" {
  description = "負荷テスト Fargate タスクの CPU ユニット (1000 ユーザー想定で 2048 以上推奨)"
  type        = number
  default     = 2048
}

variable "load_task_memory" {
  description = "負荷テスト Fargate タスクのメモリ (MiB)"
  type        = number
  default     = 4096
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
