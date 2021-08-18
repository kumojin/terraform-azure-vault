#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Nginx
# ref. https://nginx.org/en/linux_packages.html
echo "deb http://nginx.org/packages/debian `lsb_release -cs` nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
printf "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx
sudo curl https://nginx.org/keys/nginx_signing.key -o /etc/apt/trusted.gpg.d/nginx_signing.asc
sudo apt-get install nginx

# Certbot
# ref. https://certbot.eff.org/lets-encrypt/debianbuster-nginx
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
