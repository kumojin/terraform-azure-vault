output "resource_group_name" {
  value = var.vault_resource_group_name
}

output "key_vault_name" {
  value = azurerm_key_vault.vault.name
}

output "lb_ip_addr" {
  value = azurerm_public_ip.vault.ip_address
}
