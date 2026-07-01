terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

locals {
  ram_enabled = var.kong_ram_principal_account_id != ""

  # 各 VPC のルートテーブルを (vpc キー × インデックス) で平坦化し、Kong ネットワーク
  # CIDR 向けルートを一意キーで管理する。キーはルートテーブル ID (apply 時まで不明) では
  # なく静的な vpc キー + index を用いる (for_each のキーは plan 時に確定する必要があるため)。
  vpc_route_tables = merge([
    for k, v in var.vpc_attachments : {
      for idx, rt in v.route_table_ids : "${k}-${idx}" => rt
    }
  ]...)
}

# -----------------------------------------------------------------------------
# Transit Gateway
#  - auto_accept_shared_attachments: Kong が RAM 共有経由で作成するアタッチメントを
#    自動承認 (手動承認 / accepter リソースを不要にする)
#  - default route table の association / propagation を有効化し、各 VPC と
#    Kong 側アタッチメント間のルートを自動的に学習させる
# -----------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name_prefix} transit gateway"
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"

  tags = merge(var.tags, { Name = "${var.name_prefix}-tgw" })
}

# -----------------------------------------------------------------------------
# 各 VPC (app / test) を TGW にアタッチ
# -----------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-vpc-attach" })
}

# -----------------------------------------------------------------------------
# 各 VPC のルートテーブル: Kong ネットワーク CIDR を TGW 経由に
#  (これにより app-vpc / test-vpc から private DCGW へ到達できる)
# -----------------------------------------------------------------------------
resource "aws_route" "to_kong_network" {
  for_each = local.vpc_route_tables

  route_table_id         = each.value
  destination_cidr_block = var.kong_network_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# -----------------------------------------------------------------------------
# RAM 共有 (Kong アカウント ID が判明している場合のみ)
#  Kong がこの TGW にアタッチメントを作成できるよう、TGW を Kong 管理 AWS
#  アカウントへ共有する。
# -----------------------------------------------------------------------------
resource "aws_ram_resource_share" "tgw" {
  count                     = local.ram_enabled ? 1 : 0
  name                      = "${var.name_prefix}-tgw-share"
  allow_external_principals = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-tgw-share" })
}

resource "aws_ram_resource_association" "tgw" {
  count              = local.ram_enabled ? 1 : 0
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

resource "aws_ram_principal_association" "kong" {
  count              = local.ram_enabled ? 1 : 0
  principal          = var.kong_ram_principal_account_id
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}
