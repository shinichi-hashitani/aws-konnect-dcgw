locals {
  name_prefix = var.project_name
}

# -----------------------------------------------------------------------------
# 1) Konnect 側: コントロールプレーン / ネットワーク / データプレーン構成
#    (TGW アタッチメントは ram_share_arn が渡された段階で作成される)
# -----------------------------------------------------------------------------
module "konnect_dcgw" {
  source = "./modules/konnect_dcgw"

  name_prefix           = local.name_prefix
  aws_region            = var.aws_region
  availability_zone_ids = var.availability_zone_ids
  network_cidr_block    = var.network_cidr_block
  control_plane_geo     = var.control_plane_geo
  gateway_version       = var.gateway_version
  api_access            = var.api_access
  base_rps              = var.base_rps

  transit_gateway_id     = module.transit_gateway.transit_gateway_id
  ram_share_arn          = module.transit_gateway.ram_share_arn
  tgw_attachment_enabled = var.kong_ram_principal_account_id != ""
  test_vpc_cidr_blocks   = [var.test_vpc_cidr_block]

  # テストアプリ (httpbin) を DCGW 経由で公開する Service / Route
  upstream_host = module.test_app_vpc.alb_dns_name
  upstream_port = var.test_app_container_port
  route_paths   = var.test_app_route_paths

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 2) テスト VPC + httpbin (ECS Fargate / 内部 ALB)
# -----------------------------------------------------------------------------
module "test_app_vpc" {
  source = "./modules/test_app_vpc"

  name_prefix           = "${local.name_prefix}-test"
  aws_region            = var.aws_region
  vpc_cidr              = var.test_vpc_cidr_block
  availability_zone_ids = var.availability_zone_ids

  # Kong ネットワーク CIDR と自 VPC からの ALB アクセスを許可
  allowed_ingress_cidrs = [var.network_cidr_block, var.test_vpc_cidr_block]

  app_image         = var.test_app_image
  container_port    = var.test_app_container_port
  health_check_path = var.test_app_health_check_path
  desired_count     = var.test_app_desired_count
  task_cpu          = var.test_app_cpu
  task_memory       = var.test_app_memory

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 3) Transit Gateway: 作成 + テスト VPC アタッチ + RAM 共有(任意) + ルート
# -----------------------------------------------------------------------------
module "transit_gateway" {
  source = "./modules/transit_gateway"

  name_prefix           = local.name_prefix
  amazon_side_asn       = var.amazon_side_asn
  vpc_id                = module.test_app_vpc.vpc_id
  attachment_subnet_ids = module.test_app_vpc.private_subnet_ids
  route_table_ids       = module.test_app_vpc.private_route_table_ids
  kong_network_cidr     = var.network_cidr_block

  kong_ram_principal_account_id = var.kong_ram_principal_account_id

  tags = var.tags
}
