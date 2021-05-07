#!/usr/bin/env bash
set -e

# Add Hashicorp’s official GPG key
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -


# Set up Hashicorp stable repository
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

# Install Vault
sudo apt-get update
sudo apt-get install vault=${1.7.1}
