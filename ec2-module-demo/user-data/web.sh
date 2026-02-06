#!/bin/bash

set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update -y
apt install -y nginx
systemctl enable nginx
systemctl start nginx
