#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -y
sudo apt-get upgrade -y

sudo -E apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    jq \
    lsb-release \
    snapd

sudo snap install core
sudo snap refresh core
