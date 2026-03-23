resource "aws_instance" "this" {
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  key_name      = var.key_name

  vpc_security_group_ids      = var.security_group_ids
  user_data                   = var.user_data
  associate_public_ip_address = false
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.volume_size
  }

  tags = {
    Name = var.name
  }
}
