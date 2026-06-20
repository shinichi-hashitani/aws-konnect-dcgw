output "control_plane_id" {
  description = "Konnect コントロールプレーン ID"
  value       = konnect_gateway_control_plane.this.id
}

output "control_plane_endpoint" {
  description = "コントロールプレーンのエンドポイント"
  value       = try(konnect_gateway_control_plane.this.config.control_plane_endpoint, null)
}

output "network_id" {
  description = "Cloud Gateway ネットワーク ID"
  value       = konnect_cloud_gateway_network.this.id
}

output "network_vpc_id" {
  description = "Kong 管理 VPC の ID (provider_metadata)"
  value       = try(konnect_cloud_gateway_network.this.provider_metadata.vpc_id, null)
}

output "configuration_id" {
  description = "Cloud Gateway 構成 ID"
  value       = konnect_cloud_gateway_configuration.this.id
}

output "gateway_service_id" {
  description = "テストアプリ用 Gateway Service の ID"
  value       = konnect_gateway_service.app.id
}

output "gateway_route_id" {
  description = "テストアプリ用 Gateway Route の ID"
  value       = konnect_gateway_route.app.id
}

output "route_paths" {
  description = "テストアプリを公開するルートのパス"
  value       = konnect_gateway_route.app.paths
}

output "public_edge_dns" {
  description = "DCGW 公開エンドポイント (Public Edge DNS)。control plane endpoint から導出"
  value       = local.public_edge_dns
}

output "transit_gateway_state" {
  description = "Konnect Transit Gateway の状態 (未作成時は null)"
  value       = local.tgw_enabled ? konnect_cloud_gateway_transit_gateway.this[0].state : null
}

output "transit_gateway_attachment_id" {
  description = "Kong が作成した TGW アタッチメント ID (未作成時は null)"
  value = local.tgw_enabled ? try(
    konnect_cloud_gateway_transit_gateway.this[0].aws_transit_gateway_response.transit_gateway_attachment_config.attachment_id,
    null
  ) : null
}
