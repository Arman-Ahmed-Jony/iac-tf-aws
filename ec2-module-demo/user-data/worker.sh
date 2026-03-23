#!/bin/bash

set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update -y
apt install -y nginx
cat > /etc/nginx/conf.d/nginx-path.conf <<'EOF'
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  location = /nginx {
    default_type text/html;
    return 200 '<html><body><h1>Nginx Server</h1><p>Served from /nginx</p></body></html>';
  }
  location / {
    return 404;
  }
}
EOF
rm -f /etc/nginx/sites-enabled/default
systemctl enable nginx
systemctl restart nginx
