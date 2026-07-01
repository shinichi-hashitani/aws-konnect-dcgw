output "cluster_name" {
  description = "テスト用 ECS クラスタ名 (Run task で選択)"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "テスト用 ECS クラスタ ARN"
  value       = aws_ecs_cluster.this.arn
}

output "connectivity_task_family" {
  description = "疎通テストのタスク定義ファミリ名 (Run task で選択)"
  value       = aws_ecs_task_definition.connectivity.family
}

output "connectivity_task_definition_arn" {
  description = "疎通テストのタスク定義 ARN"
  value       = aws_ecs_task_definition.connectivity.arn
}

output "load_task_family" {
  description = "負荷テスト (Locust) のタスク定義ファミリ名 (Run task で選択)"
  value       = aws_ecs_task_definition.load.family
}

output "load_task_definition_arn" {
  description = "負荷テスト (Locust) のタスク定義 ARN"
  value       = aws_ecs_task_definition.load.arn
}

output "security_group_id" {
  description = "テストタスク用セキュリティグループ ID (Run task のネットワーク設定で選択)"
  value       = aws_security_group.task.id
}

output "log_group_name" {
  description = "テストタスクの CloudWatch Logs グループ名"
  value       = aws_cloudwatch_log_group.this.name
}
