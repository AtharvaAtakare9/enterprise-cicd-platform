terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  backend "s3" {
    bucket = "expense-tracker-tfstate"
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "../../modules/vpc"
  name   = "expense-tracker"
  cidr   = "10.0.0.0/16"
  azs    = ["us-east-1a", "us-east-1b"]
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "expense-tracker-backend"
}

module "eks" {
  source       = "../../modules/eks"
  cluster_name = "expense-tracker-eks"
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnet_ids
}

module "alb" {
  source            = "../../modules/alb"
  name              = "expense-tracker"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

module "rds" {
  source              = "../../modules/rds"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  allowed_cidr        = "10.0.0.0/16"
}

output "ecr_repository_url" { value = module.ecr.repository_url }
output "eks_cluster_name"   { value = module.eks.cluster_name }
output "alb_dns_name"       { value = module.alb.alb_dns_name }
output "db_endpoint"        { value = module.rds.endpoint }
output "db_port"            { value = module.rds.port }
output "db_name"            { value = module.rds.db_name }
output "db_username"        { value = module.rds.username }
output "db_password" {
  value     = module.rds.password
  sensitive = true
}
