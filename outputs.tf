# ----- Konnect -----
output "konnect_control_plane_id" {
  description = "Konnect コントロールプレーン ID"
  value       = module.konnect_dcgw.control_plane_id
}

output "konnect_control_plane_endpoint" {
  description = "コントロールプレーンのエンドポイント"
  value       = module.konnect_dcgw.control_plane_endpoint
}

output "konnect_network_id" {
  description = "Cloud Gateway ネットワーク ID"
  value       = module.konnect_dcgw.network_id
}

output "konnect_network_vpc_id" {
  description = "Kong 管理 VPC ID"
  value       = module.konnect_dcgw.network_vpc_id
}

output "konnect_transit_gateway_state" {
  description = "Konnect Transit Gateway の状態 (ready が正常)"
  value       = module.konnect_dcgw.transit_gateway_state
}

# ----- テストアプリ -----
output "test_app_alb_dns_name" {
  description = "httpbin 内部 ALB の DNS 名。Kong のサービス upstream に設定する"
  value       = module.test_app_vpc.alb_dns_name
}

output "konnect_gateway_route_paths" {
  description = "DCGW で httpbin を公開するルートのパス"
  value       = module.konnect_dcgw.route_paths
}

output "dcgw_public_edge_dns" {
  description = "DCGW 公開エンドポイント (Public Edge DNS)。自前ドメイン不要。UI: Connect > Public Edge DNS と一致"
  value       = module.konnect_dcgw.public_edge_dns
}

output "dcgw_test_url" {
  description = "httpbin への疎通テスト URL (そのまま curl 可能)"
  value = try(
    "https://${module.konnect_dcgw.public_edge_dns}${module.konnect_dcgw.route_paths[0]}/get",
    null
  )
}

output "test_vpc_id" {
  description = "テスト VPC ID"
  value       = module.test_app_vpc.vpc_id
}

# ----- Transit Gateway -----
output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = module.transit_gateway.transit_gateway_id
}

output "ram_share_arn" {
  description = "TGW を共有する RAM リソースシェア ARN (RAM 共有未設定時は空文字)"
  value       = module.transit_gateway.ram_share_arn
}

# ----- 運用ヒント -----
output "next_step_hint" {
  description = "次に行うべき操作のヒント"
  value       = module.transit_gateway.ram_enabled ? "RAM 共有済み。konnect_transit_gateway_state が 'ready' か確認してください。" : "kong_ram_principal_account_id が未設定です。Konnect UI でネットワークの Kong AWS アカウント ID を確認し、TF_VAR_kong_ram_principal_account_id に設定して再 apply してください。"
}
