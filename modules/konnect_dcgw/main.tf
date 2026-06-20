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

  tgw_enabled = var.ram_share_arn != ""
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
