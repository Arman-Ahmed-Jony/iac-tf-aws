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

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidr   = "10.0.1.0/24"
  public_subnet_cidr_2 = "10.0.2.0/24"
  az                   = "us-west-1a"
  az_2                 = "us-west-1c"
  name                 = "demo-vpc"
}

module "alb_sg" {
  source = "./modules/security_group"

  name   = "alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

module "web_sg" {
  source = "./modules/security_group"

  name   = "web-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      from_port                = 80
      to_port                  = 80
      protocol                 = "tcp"
      source_security_group_id = module.alb_sg.sg_id
    }
  ]
}

module "worker_sg" {
  source = "./modules/security_group"

  name   = "worker-sg"
  vpc_id = module.vpc.vpc_id

  ingress_rules = [
    {
      from_port                = 80
      to_port                  = 80
      protocol                 = "tcp"
      source_security_group_id = module.alb_sg.sg_id
    }
  ]
}

module "web_keypair" {
  source = "./modules/keypair"

  key_name         = "web-key"
  private_key_path = "keys/web-key.pem"
}

module "worker_keypair" {
  source = "./modules/keypair"

  key_name         = "worker-key"
  private_key_path = "keys/worker-key.pem"
}

module "web" {
  source = "./modules/ec2"

  ami           = var.web_ami
  instance_type = "t3a.micro"
  subnet_id     = module.vpc.public_subnet_id
  key_name      = module.web_keypair.key_name
  volume_size   = 10
  name          = "apache-server"

  security_group_ids = [module.web_sg.sg_id]
  user_data          = file("user-data/web.sh")
}

module "worker" {
  source = "./modules/ec2"

  ami           = var.worker_ami
  instance_type = "t3a.micro"
  subnet_id     = module.vpc.public_subnet_id
  key_name      = module.worker_keypair.key_name
  volume_size   = 10
  name          = "nginx-server"

  security_group_ids = [module.worker_sg.sg_id]
  user_data          = file("user-data/worker.sh")
}

resource "aws_lb" "web" {
  name               = "web-routing-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.alb_sg.sg_id]
  subnets = [
    module.vpc.public_subnet_id,
    module.vpc.public_subnet_id_2
  ]
}

resource "aws_lb_target_group" "apache" {
  name        = "apache-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    path = "/apache"
  }
}

resource "aws_lb_target_group" "nginx" {
  name        = "nginx-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    path = "/nginx"
  }
}

resource "aws_lb_target_group_attachment" "apache" {
  target_group_arn = aws_lb_target_group.apache.arn
  target_id        = module.web.instance_id
  port             = 80
}

resource "aws_lb_target_group_attachment" "nginx" {
  target_group_arn = aws_lb_target_group.nginx.arn
  target_id        = module.worker.instance_id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Use /apache or /nginx"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "apache" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apache.arn
  }

  condition {
    path_pattern {
      values = ["/apache*"]
    }
  }
}

resource "aws_lb_listener_rule" "nginx" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }

  condition {
    path_pattern {
      values = ["/nginx*"]
    }
  }
}
