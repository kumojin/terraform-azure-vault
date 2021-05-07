#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo rm /boot/grub/menu.lst

sudo -E apt-get upgrade -y
sudo -E apt-get install -y apt-transport-https \
    software-properties-common \
    ntp \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Disable daily apt unattended updates.
echo 'APT::Periodic::Enable "0";' >> /etc/apt/apt.conf.d/10periodic
