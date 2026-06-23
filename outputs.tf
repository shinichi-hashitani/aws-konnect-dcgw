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

# ----- DCGW エンドポイント -----
output "dcgw_api_access" {
  description = "DCGW の公開方法 (private = 閉塞構成。外部公開エンドポイントなし)"
  value       = var.api_access
}

output "konnect_gateway_route_paths" {
  description = "DCGW で httpbin を公開するルートのパス"
  value       = module.konnect_dcgw.route_paths
}

output "dcgw_public_edge_dns" {
  description = "DCGW 公開エンドポイント (Public Edge DNS)。api_access が public/public+private の場合のみ有効。private では外部から解決できない"
  value       = var.api_access == "private" ? null : module.konnect_dcgw.public_edge_dns
}

output "dcgw_public_test_url" {
  description = "public 公開時の httpbin /anything エコー疎通テスト URL。private 構成では null (閉域網内 test-vpc から実行する)"
  value = var.api_access == "private" ? null : try(
    "https://${module.konnect_dcgw.public_edge_dns}${module.konnect_dcgw.route_paths[0]}",
    null
  )
}

# ----- アプリ (httpbin) -----
output "app_alb_dns_name" {
  description = "httpbin 内部 ALB の DNS 名 (Kong サービスの upstream)"
  value       = module.app_vpc.alb_dns_name
}

output "app_vpc_id" {
  description = "app-vpc (httpbin) の ID"
  value       = module.app_vpc.vpc_id
}

# ----- テスト実行用 VPC -----
output "test_vpc_id" {
  description = "test-vpc (テストクライアント用) の ID"
  value       = module.test_vpc.vpc_id
}

output "test_vpc_private_subnet_ids" {
  description = "test-vpc の private サブネット ID (テストクライアント配置用)"
  value       = module.test_vpc.private_subnet_ids
}

# ----- Transit Gateway -----
output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = module.transit_gateway.transit_gateway_id
}

output "tgw_vpc_attachment_ids" {
  description = "各 VPC の TGW アタッチメント ID (キー: app / test)"
  value       = module.transit_gateway.vpc_attachment_ids
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
