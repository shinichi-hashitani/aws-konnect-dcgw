terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# =============================================================================
# テスト実行タスク (ECS Fargate)
#  test-vpc 内で実行し、TGW 経由で private DCGW -> app (httpbin /anything) へ
#  リクエストする。管理者が ECS コンソールの「タスクを実行」から起動する。
#  パラメータ (回数・接続先など) は環境変数で渡し、Run task UI で上書き可能。
#
#  本モジュールは現状 (1) 疎通テスト を定義する。(2) 負荷テスト は後続で追加する。
# =============================================================================

locals {
  # 疎通テスト: TARGET_URL へ REQUEST_COUNT 回リクエストし、200 以外を NG として集計。
  # NG が 1 件でもあれば非ゼロ終了 (タスク失敗) させ、コンソール上で失敗が分かるようにする。
  # Terraform heredoc のため、シェル変数は $$、curl の書式 %{...} は %%{...} でエスケープ。
  connectivity_script = <<-SCRIPT
    set -eu
    : "$${TARGET_URL:?TARGET_URL must be set (e.g. https://<dcgw-edge>/echo)}"
    COUNT="$${REQUEST_COUNT:-10}"
    SLEEP_SECONDS="$${SLEEP_SECONDS:-1}"
    TIMEOUT_SECONDS="$${TIMEOUT_SECONDS:-10}"

    echo "[connectivity] target=$${TARGET_URL} count=$${COUNT} timeout=$${TIMEOUT_SECONDS}s"
    ok=0
    ng=0
    i=1
    while [ "$$i" -le "$${COUNT}" ]; do
      code=$$(curl -ksS -o /dev/null -w '%%{http_code}' --max-time "$${TIMEOUT_SECONDS}" "$${TARGET_URL}" || echo 000)
      if [ "$$code" = "200" ]; then
        ok=$$((ok + 1))
        echo "[$$i/$${COUNT}] OK ($$code)"
      else
        ng=$$((ng + 1))
        echo "[$$i/$${COUNT}] NG ($$code)"
      fi
      i=$$((i + 1))
      if [ "$$i" -le "$${COUNT}" ]; then sleep "$${SLEEP_SECONDS}"; fi
    done
    echo "[connectivity] result ok=$${ok} ng=$${ng} total=$${COUNT}"
    [ "$$ng" -eq 0 ]
  SCRIPT

  # 負荷テスト用 locustfile (Python)。/echo へ GET し続けるだけの単純なエコー負荷。
  # private DCGW の証明書差異を避けるため TLS 検証は無効化 (curl -k 相当)。
  # ※ Python コードには Terraform の補間記号 ${ } / %{ } を含めないこと。
  locustfile = <<-PY
    import os
    import urllib3
    from locust import HttpUser, task, between

    urllib3.disable_warnings()

    TARGET_PATH = os.environ.get("TARGET_PATH", "/echo")

    class EchoUser(HttpUser):
        wait_time = between(0.1, 0.5)

        def on_start(self):
            self.client.verify = False

        @task
        def echo(self):
            self.client.get(TARGET_PATH, name=TARGET_PATH)
  PY

  # 起動スクリプト: locustfile を書き出してから headless で Locust を実行する。
  # パラメータは環境変数 (USERS / SPAWN_RATE / RUN_TIME / TARGET_HOST / TARGET_PATH) で受け取る。
  # --processes -1 で全コアにワーカーを分散し、現実的な同時接続を捌く。
  load_script = <<-SCRIPT
    set -eu
    : "$${TARGET_HOST:?TARGET_HOST must be set (e.g. https://<dcgw-edge>)}"
    USERS="$${USERS:-200}"
    SPAWN_RATE="$${SPAWN_RATE:-50}"
    RUN_TIME="$${RUN_TIME:-5m}"
    export TARGET_PATH="$${TARGET_PATH:-/echo}"

    cat > /tmp/locustfile.py <<'PYEOF'
${local.locustfile}
PYEOF

    echo "[load] host=$${TARGET_HOST} path=$${TARGET_PATH} users=$${USERS} spawn-rate=$${SPAWN_RATE} run-time=$${RUN_TIME}"
    exec locust -f /tmp/locustfile.py --headless \
      --host "$${TARGET_HOST}" \
      --users "$${USERS}" \
      --spawn-rate "$${SPAWN_RATE}" \
      --run-time "$${RUN_TIME}" \
      --processes -1 \
      --stop-timeout 30
  SCRIPT
}

# -----------------------------------------------------------------------------
# ECS クラスタ (テスト用)
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"
  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Logs
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# タスク実行ロール (イメージ取得 / ログ出力)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# -----------------------------------------------------------------------------
# テストタスク用セキュリティグループ
#  ingress は不要 (クライアントから外向きにのみ通信)。egress は全許可
#  (Kong 網へは TGW 経由、イメージ取得は NAT 経由)。
# -----------------------------------------------------------------------------
resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task-sg"
  description = "Test client tasks in test-vpc (egress only)"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (TGW to Kong network / NAT to internet)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-task-sg" })
}

# -----------------------------------------------------------------------------
# (1) 疎通テスト タスク定義
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "connectivity" {
  family                   = "${var.name_prefix}-connectivity"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([
    {
      name       = "connectivity"
      image      = var.image
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.connectivity_script]
      environment = [
        { name = "TARGET_URL", value = var.target_url },
        { name = "REQUEST_COUNT", value = tostring(var.request_count) },
        { name = "SLEEP_SECONDS", value = tostring(var.sleep_seconds) },
        { name = "TIMEOUT_SECONDS", value = tostring(var.timeout_seconds) },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "connectivity"
        }
      }
    }
  ])

  tags = var.tags
}

# -----------------------------------------------------------------------------
# (2) 負荷テスト タスク定義 (Locust / headless)
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "load" {
  family                   = "${var.name_prefix}-load"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.load_task_cpu
  memory                   = var.load_task_memory
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([
    {
      name       = "load"
      image      = var.load_image
      essential  = true
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.load_script]
      environment = [
        { name = "TARGET_HOST", value = var.load_target_host },
        { name = "TARGET_PATH", value = var.load_target_path },
        { name = "USERS", value = tostring(var.load_users) },
        { name = "SPAWN_RATE", value = tostring(var.load_spawn_rate) },
        { name = "RUN_TIME", value = var.load_run_time },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "load"
        }
      }
    }
  ])

  tags = var.tags
}
