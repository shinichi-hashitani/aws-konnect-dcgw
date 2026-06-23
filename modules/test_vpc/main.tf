terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# -----------------------------------------------------------------------------
# テスト実行用 VPC (ネットワークのみ)
#  閉域網内からテストを実行するクライアントを配置するための VPC。
#  テストクライアント (EC2 / ECS など) は後続タスクで private サブネットに追加する。
#  この VPC は TGW 経由で Kong ネットワーク (private DCGW) へ到達する。
# -----------------------------------------------------------------------------

locals {
  az_count = length(var.availability_zone_ids)

  # VPC を /26 サブネットに分割 (app_vpc と同じ方式)。
  # public を先頭、private を AZ 数ぶんオフセットして連続配置する。
  subnet_newbits       = 26 - tonumber(split("/", var.vpc_cidr)[1])
  public_subnet_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i)]
  private_subnet_cidrs = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i + local.az_count)]
}

# -----------------------------------------------------------------------------
# VPC + サブネット
# -----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "public" {
  count                = local.az_count
  vpc_id               = aws_vpc.this.id
  cidr_block           = local.public_subnet_cidrs[count.index]
  availability_zone_id = var.availability_zone_ids[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${var.availability_zone_ids[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count                = local.az_count
  vpc_id               = aws_vpc.this.id
  cidr_block           = local.private_subnet_cidrs[count.index]
  availability_zone_id = var.availability_zone_ids[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-${var.availability_zone_ids[count.index]}"
    Tier = "private"
  })
}

# -----------------------------------------------------------------------------
# IGW + NAT
#  テストクライアントが private サブネットからツール取得などで egress するための経路。
#  (DCGW への閉域アクセスは TGW 経由。インターネット ingress は無し)
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nat-eip" })
}

# コスト最適化のため NAT は 1 つ (public[0] に配置)。
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(var.tags, { Name = "${var.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# ルートテーブル
#  - public: IGW 向けデフォルトルート
#  - private: NAT 向けデフォルトルート (Kong 網への TGW ルートは transit_gateway
#    モジュールが route_table_ids を受け取り追加する)
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-private-rt" })
}

resource "aws_route" "private_internet" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
