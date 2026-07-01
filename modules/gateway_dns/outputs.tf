output "zone_id" {
  description = "Private Hosted Zone の ID (未作成時は null)"
  value       = var.enabled ? aws_route53_zone.this[0].zone_id : null
}

output "fqdn" {
  description = "解決対象の DCGW プロキシ FQDN"
  value       = var.record_name
}

output "record_ips" {
  description = "FQDN に登録した private IP"
  value       = var.enabled ? var.record_ips : []
}
