output "vpc_id" {
  description = "テスト実行用 VPC の ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "テスト実行用 VPC の CIDR"
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "プライベートサブネット ID (TGW アタッチメント / テストクライアント配置用)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "パブリックサブネット ID"
  value       = aws_subnet.public[*].id
}

output "private_route_table_ids" {
  description = "プライベートルートテーブル ID (Kong 網への TGW ルート追加用)"
  value       = [aws_route_table.private.id]
}
