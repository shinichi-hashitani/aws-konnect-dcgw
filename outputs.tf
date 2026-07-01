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
  description = "test-vpc の private サブネット ID (Run task のネットワーク設定で選択)"
  value       = module.test_vpc.private_subnet_ids
}

# ----- テスト実行タスク (ECS Run task で使用) -----
output "test_ecs_cluster_name" {
  description = "テスト用 ECS クラスタ名"
  value       = module.test_tasks.cluster_name
}

output "test_connectivity_task_family" {
  description = "疎通テストのタスク定義ファミリ名"
  value       = module.test_tasks.connectivity_task_family
}

output "test_load_task_family" {
  description = "負荷テスト (Locust) のタスク定義ファミリ名"
  value       = module.test_tasks.load_task_family
}

output "test_task_security_group_id" {
  description = "テストタスク用セキュリティグループ ID"
  value       = module.test_tasks.security_group_id
}

# ----- DCGW プロキシ Private DNS -----
output "gateway_private_dns_fqdn" {
  description = "PHZ で private IP へ解決される DCGW プロキシ FQDN"
  value       = module.gateway_dns.fqdn
}

output "gateway_private_dns_ips" {
  description = "FQDN に登録した DCGW データプレーン内部 LB の private IP"
  value       = module.gateway_dns.record_ips
}

output "test_run_task_hint" {
  description = "ECS コンソールでの疎通テスト実行手順 (概要)"
  value = join(" / ", [
    "ECS > クラスタ: ${module.test_tasks.cluster_name}",
    "タスクを実行 > 起動タイプ FARGATE",
    "タスク定義: ${module.test_tasks.connectivity_task_family}",
    "VPC: test-vpc (${module.test_vpc.vpc_id})",
    "サブネット: test_vpc_private_subnet_ids",
    "SG: ${module.test_tasks.security_group_id}",
    "パブリックIP: 無効",
    "上書き可: 環境変数 TARGET_URL / REQUEST_COUNT",
  ])
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
