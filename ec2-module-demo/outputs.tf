output "web_ip" {
  value = module.web.public_ip
}

output "worker_ip" {
  value = module.worker.public_ip
}
