#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "name" {}
variable "region" {}
variable "domain" {}
variable "subdomain" {}
variable "db_name" {}
variable "db_username" {}
variable "db_password" {}
variable "engine" {}
variable "engine_version" {}
variable "db_instance" {}
variable "db_port" {}
variable "migration_url" {}
variable "http_server_address" {}
variable "grpc_server_address" {}
variable "http_port" {}
variable "grpc_port" {}

terraform {
  required_version = "= 1.7.1"
}

provider "aws" {
  region = var.region
}

module "network" {
  source = "./network"

  name = var.name
}

module "subdomain_acm" {
  source = "./subdomain_acm"

  domain    = var.domain
  subdomain = var.subdomain
}

module "elb" {
  source = "./elb"

  name              = var.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  acm_id            = module.subdomain_acm.acm_id
  domain            = var.domain
  subdomain         = var.subdomain
  subdomain_zone_id = module.subdomain_acm.subdomain_zone_id
}

module "rds" {
  source = "./rds"

  name               = var.name
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  engine             = var.engine
  engine_version     = var.engine_version
  db_instance        = var.db_instance
  db_port            = var.db_port
  vpc_id             = module.network.vpc_id
  alb_security_group = module.elb.alb_security_group
  private_subnet_ids = module.network.private_subnet_ids
}

module "ecs_cluster" {
  source = "./ecs_cluster"

  name = var.name
}

module "ecs_api" {
  source = "./ecs_api"

  name               = var.name
  cluster_name       = module.ecs_cluster.cluster_name
  vpc_id             = module.network.vpc_id
  http_listener_arn  = module.elb.http_listener_arn
  https_listener_arn = module.elb.https_listener_arn
  subnet_ids         = module.network.public_subnet_ids

  db_host     = module.rds.db_address
  db_port     = var.db_port
  db_name     = var.db_name
  db_user     = var.db_username
  db_password = var.db_password
  # db_password_arn = module.rds.db_password_arn
  migration_url = var.migration_url
  http_server_address = var.http_server_address
  grpc_server_address = var.grpc_server_address
  http_port   = var.http_port
  grpc_port   = var.grpc_port
}
