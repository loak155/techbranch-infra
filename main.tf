
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 4.1.0"
    }
  }
}

locals {
  app_name = "techbranch"
  host_domain = "techbranch.link"
  app_domain_name = "app.techbranch.link"
  api_domain_name = "api.techbranch.link"
  ssm_parameter_store_base = "/techbranch"
}

provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      Name = local.app_name
    }
  }
}