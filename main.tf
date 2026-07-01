locals {
  name_prefix = var.project_name

  # Kong データプレーンから TGW 経由でルートする宛先 (app-vpc / test-vpc)。
  routed_cidr_blocks = [var.app_vpc_cidr_block, var.test_vpc_cidr_block]
}

# -----------------------------------------------------------------------------
# 1) Konnect 側: コントロールプレーン / ネットワーク / データプレーン構成
#    (api_access=private で外部公開エンドポイントを持たない閉塞構成)
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
  routed_cidr_blocks     = local.routed_cidr_blocks

  # httpbin を DCGW 経由で公開する Service / Route (upstream = app-vpc 内部 ALB)
  # 公開パス /echo を Service path /anything (エコー) へマップ (strip_path=true)
  upstream_host    = module.app_vpc.alb_dns_name
  upstream_port    = var.app_container_port
  upstream_path    = var.app_upstream_path
  route_paths      = var.app_route_paths
  route_strip_path = var.app_route_strip_path
  route_protocols  = var.app_route_protocols

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 2) app-vpc: httpbin (ECS Fargate / 内部 ALB)
# -----------------------------------------------------------------------------
module "app_vpc" {
  source = "./modules/app_vpc"

  name_prefix           = "${local.name_prefix}-app"
  aws_region            = var.aws_region
  vpc_cidr              = var.app_vpc_cidr_block
  availability_zone_ids = var.availability_zone_ids

  # ALB へは Kong 網 (DCGW) からアクセスされる。自 VPC からのアクセスも許可。
  allowed_ingress_cidrs = [var.network_cidr_block, var.app_vpc_cidr_block]

  app_image         = var.app_image
  container_port    = var.app_container_port
  health_check_path = var.app_health_check_path
  desired_count     = var.app_desired_count
  task_cpu          = var.app_cpu
  task_memory       = var.app_memory

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 3) test-vpc: 閉域網内からテストを実行するクライアント用 VPC (ネットワークのみ)
#    テストクライアント本体は後続タスクで追加する。
# -----------------------------------------------------------------------------
module "test_vpc" {
  source = "./modules/test_vpc"

  name_prefix           = "${local.name_prefix}-test"
  vpc_cidr              = var.test_vpc_cidr_block
  availability_zone_ids = var.availability_zone_ids

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 4) Transit Gateway: 作成 + app-vpc / test-vpc アタッチ + RAM 共有(任意) + ルート
# -----------------------------------------------------------------------------
module "transit_gateway" {
  source = "./modules/transit_gateway"

  name_prefix       = local.name_prefix
  amazon_side_asn   = var.amazon_side_asn
  kong_network_cidr = var.network_cidr_block

  vpc_attachments = {
    app = {
      vpc_id          = module.app_vpc.vpc_id
      subnet_ids      = module.app_vpc.private_subnet_ids
      route_table_ids = module.app_vpc.private_route_table_ids
    }
    test = {
      vpc_id          = module.test_vpc.vpc_id
      subnet_ids      = module.test_vpc.private_subnet_ids
      route_table_ids = module.test_vpc.private_route_table_ids
    }
  }

  kong_ram_principal_account_id = var.kong_ram_principal_account_id

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 5) テスト実行タスク (ECS Fargate) — test-vpc で実行し DCGW 経由で app を叩く
#    管理者が ECS コンソールの「タスクを実行」から起動する。
# -----------------------------------------------------------------------------
module "test_tasks" {
  source = "./modules/test_tasks"

  name_prefix = "${local.name_prefix}-test"
  aws_region  = var.aws_region
  vpc_id      = module.test_vpc.vpc_id
  image       = var.test_client_image

  # 接続先 URL。test_target_url 指定時はそれを、未指定時は DCGW エッジ + 公開パスから導出。
  # FQDN の名前解決は gateway_dns モジュールの Route53 PHZ が担う (private IP へ解決)。
  target_url    = var.test_target_url != "" ? var.test_target_url : try("https://${module.konnect_dcgw.public_edge_dns}${var.app_route_paths[0]}", "")
  request_count = var.test_request_count

  # 負荷テスト (Locust): host はベース URL、path は公開パス。
  load_target_host = var.test_load_target_host != "" ? var.test_load_target_host : try("https://${module.konnect_dcgw.public_edge_dns}", "")
  load_target_path = var.app_route_paths[0]
  load_users       = var.test_load_users
  load_spawn_rate  = var.test_load_spawn_rate
  load_run_time    = var.test_load_run_time

  tags = var.tags
}

# -----------------------------------------------------------------------------
# 6) DCGW プロキシ用 Route53 Private Hosted Zone
#    private 構成では DCGW の FQDN が公開 DNS に無いため、自アカウントに PHZ を作り
#    app-vpc / test-vpc に関連付けて FQDN をデータプレーン内部 LB の private IP へ解決。
#    IP は konnect_cloud_gateway_configuration の属性から取得 (apply ごとに最新化)。
# -----------------------------------------------------------------------------
module "gateway_dns" {
  source = "./modules/gateway_dns"

  enabled     = var.enable_gateway_private_dns
  zone_name   = var.gateway_dns_zone_name
  record_name = try(module.konnect_dcgw.public_edge_dns, "")
  record_ips  = try(module.konnect_dcgw.dataplane_private_ips, [])
  vpc_ids     = [module.app_vpc.vpc_id, module.test_vpc.vpc_id]

  tags = var.tags
}
