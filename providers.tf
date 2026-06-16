provider "aws" {
  region = var.aws_region

  # 認証情報は環境変数から読み込みます (.env 参照):
  #   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
  #   もしくは AWS_PROFILE

  default_tags {
    tags = var.tags
  }
}

provider "konnect" {
  server_url = var.konnect_server_url

  # personal_access_token は環境変数 KONNECT_TOKEN から自動的に読み込まれます。
  # 明示的に渡したい場合は var.konnect_personal_access_token を設定してください
  # (null の場合は環境変数にフォールバックします)。
  personal_access_token = var.konnect_personal_access_token
}
