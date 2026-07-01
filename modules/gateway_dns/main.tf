terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# =============================================================================
# DCGW プロキシ用 Route53 Private Hosted Zone
#  api_access=private の DCGW は FQDN (<id>.gateways.konghq.com) を公開 DNS に
#  持たないため、自アカウントに PHZ を作成して app-vpc / test-vpc に関連付け、
#  FQDN をデータプレーン内部 LB の private IP へ解決させる。
#  IP は Konnect が返す "internal load balancer" の private IP なので比較的安定。
#  変動しても record_ips (konnect_cloud_gateway_configuration の属性) 経由で
#  terraform apply のたびに最新化される。
# =============================================================================

resource "aws_route53_zone" "this" {
  count   = var.enabled ? 1 : 0
  name    = var.zone_name
  comment = "Private zone for DCGW proxy resolution (managed by Terraform)"

  dynamic "vpc" {
    for_each = var.vpc_ids
    content {
      vpc_id = vpc.value
    }
  }

  tags = merge(var.tags, { Name = var.zone_name })
}

resource "aws_route53_record" "gateway" {
  count   = var.enabled ? 1 : 0
  zone_id = aws_route53_zone.this[0].zone_id
  name    = var.record_name
  type    = "A"
  ttl     = var.ttl
  records = var.record_ips
}
