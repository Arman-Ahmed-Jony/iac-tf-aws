#!/bin/bash

set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update -y
apt install -y apache2
mkdir -p /var/www/html
cat > /var/www/html/apache.html <<'EOF'
<html><body><h1>Apache Server</h1><p>Served from /apache</p></body></html>
EOF
cat > /etc/apache2/conf-available/apache-path.conf <<'EOF'
Alias /apache /var/www/html/apache.html
EOF
a2enconf apache-path
systemctl enable apache2
systemctl restart apache2
