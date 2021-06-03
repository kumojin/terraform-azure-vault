variable "location" {
  description = "The Azure Region in which all resources in this example should be created."
  default = "Canada Central"
}

# Azure Service account to use
variable "azure_tenant_id" {}
variable "azure_client_id" {}
variable "azure_client_secret" {
  sensitive = true
}
variable "azure_subscription_id" {}

variable "vault_resource_group_name" {
  description = "The resource group for deploying vault"
  default = "vault-rg"
}

variable "vault_instances_sku" {
  description = "The Vault VM size SKU"
  default = "Standard_DS2_v2"
}

variable "vault_instances_count" {
  description = "The number of Vault instances"
  default = 3
}

variable "vault_instances_admin_user" {
  description = "The SSH admin user name"
  default = "vm-user"
}

variable "vault_instances_admin_ssh_key_path" {
  description = "The SSH admin user public key path"
  default = "~/.ssh/id_rsa.pub"
}

variable "vault_source_image_id" {
  description = "Image ID created with packer"
}

variable "vault_key_vault_name" {
  description = "Name of Vault Key Vault, the name will be suffixed with a random 4b hex"
  default = "vault-kv"
}

variable "vault_public_domain_name" {
  description = "Domain name label for vault public IP"
}
