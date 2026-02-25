terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-1"
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr           = "10.0.0.0/16"
  public_subnet_cidr = "10.0.1.0/24"
  az                 = "us-west-1a"
  name               = "arman-ahmed-demo-vpc"
}

module "web_sg" {
  source = "./modules/security_group"

  name   = "arman-ahmed-web-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

module "worker_sg" {
  source = "./modules/security_group"

  name   = "arman-ahmed-worker-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

module "web_keypair" {
  source = "./modules/keypair"

  key_name         = "arman-ahmed-web-key"
  private_key_path = "keys/arman-ahmed-web-key.pem"
}

module "worker_keypair" {
  source = "./modules/keypair"

  key_name         = "arman-ahmed-worker-key"
  private_key_path = "keys/arman-ahmed-worker-key.pem"
}

module "web" {
  source = "./modules/ec2"

  ami           = var.web_ami
  instance_type = "t3a.micro"
  subnet_id     = module.vpc.public_subnet_id
  key_name      = module.web_keypair.key_name
  volume_size   = 10
  name          = "arman-ahmed-web-server"

  security_group_ids = [module.web_sg.sg_id]
  user_data          = file("user-data/web.sh")
}

module "worker" {
  source = "./modules/ec2"

  ami           = var.worker_ami
  instance_type = "t3a.micro"
  subnet_id     = module.vpc.public_subnet_id
  key_name      = module.worker_keypair.key_name
  volume_size   = 30
  name          = "arman-ahmed-worker-server"

  security_group_ids = [module.worker_sg.sg_id]
  user_data          = file("user-data/worker.sh")
}
