resource "azurerm_virtual_network" "vault" {
  name                = "vault-network"
  resource_group_name = azurerm_resource_group.vault.name
  location            = azurerm_resource_group.vault.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.vault.name
  virtual_network_name = azurerm_virtual_network.vault.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "vault" {
  name                = "vault-nsg"
  location            = azurerm_resource_group.vault.location
  resource_group_name = azurerm_resource_group.vault.name

  security_rule {
    name                       = "vault"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8200"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ssh"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "50000-50099"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vault" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.vault.id
}


data "template_file" "setup" {
  template = file("${path.module}/setup.tpl")

  vars = {
    resource_group_name = var.vault_resource_group_name
    vmss_name           = "vault-vmss"
    tenant_id           = var.azure_tenant_id
    subscription_id     = var.azure_subscription_id
    client_id           = var.azure_client_id
    client_secret       = var.azure_client_secret
    vault_name          = azurerm_key_vault.vault.name
    key_name            = azurerm_key_vault_key.vault-key.name
  }
}

resource "azurerm_linux_virtual_machine_scale_set" "vault" {
  name                = "vault-vmss"
  resource_group_name = azurerm_resource_group.vault.name
  location            = azurerm_resource_group.vault.location
  sku                 = var.vault_instances_sku
  instances           = var.vault_instances_count
  admin_username      = var.vault_instances_admin_user
  custom_data         = base64encode(data.template_file.setup.rendered)

  admin_ssh_key {
    username   = var.vault_instances_admin_user
    public_key = file(var.vault_instances_admin_ssh_key_path)
  }

  source_image_id = var.vault_source_image_id

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "vault-internal-network"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.internal.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
      load_balancer_inbound_nat_rules_ids = [azurerm_lb_nat_pool.ssh.id]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_lb.vault,
    azurerm_lb_backend_address_pool.bpepool,
    azurerm_lb_nat_pool.ssh
  ]
}

resource "azurerm_role_assignment" "vault-vmss" {
  scope                = azurerm_resource_group.vault.id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_virtual_machine_scale_set.vault.identity[0].principal_id
}
