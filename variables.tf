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
  description = "Vault's SSH admin user name"
  default = "vm-user"
}

variable "vault_instances_admin_ssh_key_path" {
  description = "Vault's SSH admin user public key path"
  default = "~/.ssh/id_rsa.pub"
}

variable "vault_source_image_id" {
  description = "Image ID created with packer"
}

variable "vault_key_vault_name" {
  description = "Name of Vault Key Vault, the name will be suffixed with a random 4b hex"
  default = "vault-kv"
}

variable "nginx_source_image_id" {
  description = "Image ID created with packer containing Nginx and Certbot"
}

variable "nginx_vm_size" {
  description = "Virtual Machine size for the Nginx server"
  default = "Standard_DS1_v2"
}

variable "nginx_vm_admin_user" {
  description = "Nginx's SSH admin user name"
  default = "vm-user"
}

variable "nginx_vm_admin_ssh_key_path" {
  description = "Nginx's SSH admin user public key path"
  default = "~/.ssh/id_rsa.pub"
}

variable "cert_domain_name" {
  description = "TLS certificate's FQDN"
}
