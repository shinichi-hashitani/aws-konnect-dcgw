terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    konnect = {
      source  = "kong/konnect"
      version = "~> 3.18"
    }
  }

  # ローカル state を使用します。チーム運用に移行する場合は、以下のような
  # S3 バックエンドへ切り替えてください(コメント解除し値を設定):
  #
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "aws-konnect-dcgw/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   dynamodb_table = "your-tflock-table"
  #   encrypt        = true
  # }
}
