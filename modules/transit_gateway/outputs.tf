output "transit_gateway_id" {
  description = "Transit Gateway の ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "Transit Gateway の ARN"
  value       = aws_ec2_transit_gateway.this.arn
}

output "ram_share_arn" {
  description = "TGW を共有する RAM リソースシェアの ARN (未作成時は空文字)"
  value       = local.ram_enabled ? aws_ram_resource_share.tgw[0].arn : ""
}

output "ram_enabled" {
  description = "RAM 共有 / Konnect TGW 作成が有効かどうか"
  value       = local.ram_enabled
}

output "test_vpc_attachment_id" {
  description = "テスト VPC の TGW アタッチメント ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.test_vpc.id
}
