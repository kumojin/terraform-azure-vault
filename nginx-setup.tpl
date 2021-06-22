#!/usr/bin/env bash

# This file will be executed as root by cloud-init.
#
# To troubleshoot the execution of this file:
#   1. access the virtual machine boot diagnostics pane in the azure portal.
#   2. ssh into the virtual machine and execute:
#      * sudo journalctl
#      * sudo journalctl -u cloud-final

set -Eeu

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 8200 ssl default_server;
    listen [::]:8200 ssl default_server;

    server_name ${cert_domain_name};

    location / {
        proxy_pass http://${vault_ip_addr}:8200;
    }

    # Redirects HTTP requests to HTTPS.
    # ref. http://nginx.org/en/docs/http/ngx_http_ssl_module.html#Nonstandard_error_codes
    error_page 497 301 =307 https://$host:$server_port$request_uri;
}
EOF

systemctl enable nginx
systemctl restart nginx
