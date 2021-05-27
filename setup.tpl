#!/usr/bin/env bash
# NB this file will be executed as root by cloud-init.
# NB to troubleshoot the execution of this file, you can:
#      1. access the virtual machine boot diagnostics pane in the azure portal.
#      2. ssh into the virtual machine and execute:
#           * sudo journalctl
#           * sudo journalctl -u cloud-final

set -Eeu

mkdir /etc/vault.d || true
mkdir -p /opt/vault || true

ip_address="$(ip addr show eth0 | perl -n -e'/ inet (\d+(\.\d+)+)/ && print $1')"

cat > /etc/vault.d/vault.hcl <<EOF
storage "raft" {
  path = "/opt/vault"
  retry_join {
    auto_join = "provider=azure tenant_id=${tenant_id} subscription_id=${subscription_id} vm_scale_set=${vmss_name} resource_group=${resource_group_name}"
    auto_join_scheme = "http"
  }
}

api_addr = "http://$ip_address:8200"
cluster_addr = "http://$ip_address:8201"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

disable_mlock = true
ui = true

seal "azurekeyvault" {
  client_id      = "${client_id}"
  client_secret  = "${client_secret}"
  tenant_id      = "${tenant_id}"
  vault_name     = "${vault_name}"
  key_name       = "${key_name}"
}

EOF

chown -R vault. /etc/vault.d
chown -R vault. /opt/vault
chmod 0644 /etc/vault.d/vault.hcl

systemctl enable vault
systemctl restart vault

cat > /etc/profile.d/vault.sh <<'EOF'
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
EOF
