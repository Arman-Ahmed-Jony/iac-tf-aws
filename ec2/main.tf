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

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "ec2-key.pem"
  file_permission = "0400"
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "terraform-demo-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

resource "aws_security_group" "web_sg" {
  name        = "terraform-web-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_instance" "web" {
  ami                         = "ami-0290e60ec230db1e4"
  instance_type               = "t3a.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.ec2_key.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash

    set -euxo pipefail
    exec > /var/log/user-data.log 2>&1
    export DEBIAN_FRONTEND=noninteractive

    apt update -y
    apt install -y nginx
    systemctl start nginx
    systemctl enable nginx
  EOF

  tags = {
    Name = "terraform-demo-ec2"
  }
}
