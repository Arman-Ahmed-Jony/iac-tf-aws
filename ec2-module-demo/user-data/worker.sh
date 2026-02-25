#!/bin/bash

set -euxo pipefail
exec > /var/log/user-data.log 2>&1

yum update -y

# Install Docker
yum install -y docker
systemctl enable docker
systemctl start docker

# Install MySQL
yum install -y mysql mysql-server
systemctl enable mysqld
systemctl start mysqld
