provider "aws" {
  region = var.aws_region

  # 認証情報は IAM Identity Center (AWS SSO) のプロファイルを使用します。
  # 環境変数 AWS_PROFILE で SSO プロファイルを指定し (.env 参照)、
  # 事前に `aws sso login --profile <name>` でトークンを取得しておきます。
  # AWS プロバイダは ~/.aws/config の SSO 設定と SSO キャッシュを自動的に読み込みます。

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
