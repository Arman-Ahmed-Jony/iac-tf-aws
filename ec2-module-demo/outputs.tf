output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_id" {
  value = module.vpc.public_subnet_id
}

output "public_subnet_id_2" {
  value = module.vpc.public_subnet_id_2
}

output "web_sg_id" {
  value = module.web_sg.sg_id
}

output "worker_sg_id" {
  value = module.worker_sg.sg_id
}

output "web_key_name" {
  value = module.web_keypair.key_name
}

output "worker_key_name" {
  value = module.worker_keypair.key_name
}

output "alb_dns_name" {
  value = aws_lb.web.dns_name
}

output "apache_url" {
  value = "http://${aws_lb.web.dns_name}/apache"
}

output "nginx_url" {
  value = "http://${aws_lb.web.dns_name}/nginx"
}
