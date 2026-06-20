terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "~> 3.18"
    }
  }
}

# -----------------------------------------------------------------------------
# Konnect とリンク済みのクラウドプロバイダアカウント (AWS) を取得。
# cloud_gateway_provider_account_id は Konnect 内部 ID であり、ユーザーの AWS
# アカウント ID とは別物。
# -----------------------------------------------------------------------------
data "konnect_cloud_gateway_provider_account_list" "this" {}

locals {
  # cloud_gateway_provider_account_id には Konnect 内部の UUID (data[].id) を渡す。
  # data[].provider_account_id は AWS アカウント番号 (例 5901...) であり別物なので使わない。
  konnect_provider_account_id = one([
    for a in data.konnect_cloud_gateway_provider_account_list.this.data : a.id
    if a.provider == "aws"
  ])

  # count は plan 時に確定する必要があるため、apply 時まで未確定の ram_share_arn では
  # なく、入力済みフラグ (tgw_attachment_enabled) で判定する。
  tgw_enabled = var.tgw_attachment_enabled

  # DCGW の公開エンドポイント (Public Edge DNS) を control plane endpoint から導出。
  # 例: control_plane_endpoint=https://e9f7281a29.us.cp.konghq.com
  #     -> 先頭ラベル e9f7281a29 -> e9f7281a29.gateways.konghq.com
  # (UI の Connect > Public Edge DNS と一致。UI が一次情報、これは利便のための導出値)
  cp_host         = try(replace(replace(konnect_gateway_control_plane.this.config.control_plane_endpoint, "https://", ""), "http://", ""), "")
  public_edge_dns = local.cp_host == "" ? null : "${split(".", local.cp_host)[0]}.gateways.konghq.com"
}

# -----------------------------------------------------------------------------
# コントロールプレーン (Cloud Gateway 有効)
# -----------------------------------------------------------------------------
resource "konnect_gateway_control_plane" "this" {
  name          = "${var.name_prefix}-cp"
  description   = "Dedicated Cloud Gateway control plane"
  cluster_type  = "CLUSTER_TYPE_CONTROL_PLANE"
  cloud_gateway = true
  auth_type     = "pinned_client_certs"

  labels = var.tags
}

# -----------------------------------------------------------------------------
# Cloud Gateway ネットワーク (Kong 管理 VPC をプロビジョニング)
# -----------------------------------------------------------------------------
resource "konnect_cloud_gateway_network" "this" {
  name                              = "${var.name_prefix}-network"
  region                            = var.aws_region
  availability_zones                = var.availability_zone_ids
  cidr_block                        = var.network_cidr_block
  cloud_gateway_provider_account_id = local.konnect_provider_account_id
}

# -----------------------------------------------------------------------------
# データプレーングループ構成 (DCGW データプレーンをデプロイ)
# -----------------------------------------------------------------------------
resource "konnect_cloud_gateway_configuration" "this" {
  control_plane_id  = konnect_gateway_control_plane.this.id
  control_plane_geo = var.control_plane_geo
  version           = var.gateway_version
  api_access        = var.api_access

  dataplane_groups = [
    {
      provider                 = "aws"
      region                   = var.aws_region
      cloud_gateway_network_id = konnect_cloud_gateway_network.this.id

      autoscale = {
        configuration_data_plane_group_autoscale_autopilot = {
          kind     = "autopilot"
          base_rps = var.base_rps
        }
      }
    }
  ]
}

# -----------------------------------------------------------------------------
# Transit Gateway アタッチメント (RAM 共有が用意できた段階で作成)
#  Kong がユーザーの TGW へアタッチメントを作成する。TGW 側で
#  auto_accept_shared_attachments を有効にしているため自動承認される。
# -----------------------------------------------------------------------------
resource "konnect_cloud_gateway_transit_gateway" "this" {
  count      = local.tgw_enabled ? 1 : 0
  network_id = konnect_cloud_gateway_network.this.id

  aws_transit_gateway = {
    name        = "${var.name_prefix}-tgw"
    cidr_blocks = var.test_vpc_cidr_blocks

    transit_gateway_attachment_config = {
      kind               = "aws-transit-gateway-attachment"
      transit_gateway_id = var.transit_gateway_id
      ram_share_arn      = var.ram_share_arn
    }
  }
}

# -----------------------------------------------------------------------------
# Gateway Service / Route (テストアプリ httpbin を DCGW 経由で公開)
#  upstream は内部 ALB。コントロールプレーンに設定が保存され、データプレーンへ同期される。
# -----------------------------------------------------------------------------
resource "konnect_gateway_service" "app" {
  control_plane_id = konnect_gateway_control_plane.this.id
  name             = "${var.name_prefix}-app"
  host             = var.upstream_host
  protocol         = var.upstream_protocol
  port             = var.upstream_port
  enabled          = true
}

resource "konnect_gateway_route" "app" {
  control_plane_id = konnect_gateway_control_plane.this.id
  name             = "${var.name_prefix}-app"
  service          = { id = konnect_gateway_service.app.id }
  paths            = var.route_paths
  strip_path       = true
  protocols        = ["http", "https"]
}
