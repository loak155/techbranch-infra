#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "name" {
  type = string
  default = "myapp"
}

variable "azs" {
  type    = list
  default = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

#--------------------------------------------------------------
# VPC
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}"
  }
}

#--------------------------------------------------------------
# Public subnet
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "publics" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.vpc.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.public_subnet_cidrs[count.index]

  tags = {
    Name = "${var.name}-public-${count.index}"
  }
}

#--------------------------------------------------------------
# Private subnet
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet

resource "aws_subnet" "privates" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.vpc.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.private_subnet_cidrs[count.index]

  tags = {
    Name = "${var.name}-private-${count.index}"
  }
}

#--------------------------------------------------------------
# Internet Gateway
# これがないと外部への通信ができない
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.name}-igw"
  }
}

#--------------------------------------------------------------
# Route Table (Internet Gateway と Public Subnet の経路)
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
# 経路情報を格納する箱
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.name}-public-rtb"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route
# 経路情報をaws_route_tableへ追加する
resource "aws_route" "public" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.igw.id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
# aws_route_tableとaws_subnetを紐づける
resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = element(aws_subnet.publics.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

#--------------------------------------------------------------
# Route Table (NAT Gateway と Private Subnet の経路)
# これにより、Private Subnetから外部へ通信が繋がるようになる
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.name}-private-rtb-${count.index}"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route
resource "aws_route" "private" {
  count = length(var.private_subnet_cidrs)

  destination_cidr_block = "0.0.0.0/0"

  route_table_id = element(aws_route_table.private.*.id, count.index)
  nat_gateway_id = element(aws_nat_gateway.nat_gateway.*.id, count.index)
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = element(aws_subnet.privates.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

#--------------------------------------------------------------
# NAT Gateway
# NAT Gatewayはネットワークアドレスを変換(NAT)するサービス
# Private Subnetから外部へ通信するために必要
# NAT Gatewayには1つのElastic IPを紐付ける必要があるので、Elastic IPも作成する
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "nat" {
  count = length(var.public_subnet_cidrs)

  domain   = "vpc"

  tags = {
    Name = "${var.name}-natgw-${count.index}"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway
resource "aws_nat_gateway" "nat_gateway" {
  count = length(var.public_subnet_cidrs)

  subnet_id     = element(aws_subnet.publics.*.id, count.index)
  allocation_id = element(aws_eip.nat.*.id, count.index)

  tags = {
    Name = "${var.name}-${count.index}"
  }
}

#--------------------------------------------------------------
# Outputs
#--------------------------------------------------------------

output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnet_ids" {
  value = [for value in aws_subnet.publics : value.id]
}

output "private_subnet_ids" {
  value = [for value in aws_subnet.privates : value.id]
}