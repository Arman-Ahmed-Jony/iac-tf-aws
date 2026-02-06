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


resource "aws_security_group" "web_sg" {
  name = "web-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "worker_sg" {
  name = "worker-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "tls_private_key" "web_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "web_private_key" {
  content         = tls_private_key.web_key.private_key_pem
  filename        = "keys/web-key.pem"
  file_permission = "0400"
}

resource "aws_key_pair" "web_key" {
  key_name   = "web-key-name"
  public_key = tls_private_key.web_key.public_key_openssh
}

resource "tls_private_key" "worker_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "worker_private_key" {
  content         = tls_private_key.worker_key.private_key_pem
  filename        = "keys/worker-key.pem"
  file_permission = "0400"
}

resource "aws_key_pair" "worker_key" {
  key_name   = "worker-key-name"
  public_key = tls_private_key.worker_key.public_key_openssh
}


module "web" {
  source = "./modules/ec2"

  ami           = var.web_ami
  instance_type = "t3.micro"
  subnet_id     = var.web_subnet_id
  key_name      = aws_key_pair.web_key.key_name
  volume_size   = 10
  name          = "web-server"

  security_group_ids = [aws_security_group.web_sg.id]
  user_data          = file("user-data/web.sh")
}

module "worker" {
  source = "./modules/ec2"

  ami           = var.worker_ami
  instance_type = "t3.small"
  subnet_id     = var.worker_subnet_id
  key_name      = aws_key_pair.worker_key.key_name
  volume_size   = 30
  name          = "worker-server"

  security_group_ids = [aws_security_group.worker_sg.id]
  user_data          = file("user-data/worker.sh")
}
