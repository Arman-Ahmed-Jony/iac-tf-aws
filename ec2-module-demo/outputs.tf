output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_id" {
  value = module.vpc.public_subnet_id
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

output "web_public_ip" {
  value = module.web.public_ip
}

output "worker_public_ip" {
  value = module.worker.public_ip
}


output "web_ssh_command" {
  value = "ssh -i keys/arman-ahmed-web-key.pem ubuntu@${module.web.public_ip}"
}

output "worker_ssh_command" {
  value = "ssh -i keys/arman-ahmed-worker-key.pem ec2-user@${module.worker.public_ip}"
}
