output "vpc_id" {
  description = "アプリ VPC の ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "アプリ VPC の CIDR"
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "プライベートサブネット ID (TGW アタッチメント用)"
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

output "alb_dns_name" {
  description = "内部 ALB の DNS 名 (Kong サービスの upstream に指定)"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "内部 ALB の ARN"
  value       = aws_lb.this.arn
}
