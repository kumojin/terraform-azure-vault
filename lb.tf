resource "azurerm_public_ip" "vault" {
  name                  = "vault-public-ip"
  location              = var.location
  resource_group_name   = azurerm_resource_group.vault.name
  allocation_method     = "Static"
  domain_name_label     = var.vaul_public_domain_name
  sku                   = "Standard"
}

resource "azurerm_lb" "vault" {
  name                = "vault-lb"
  location            = var.location
  resource_group_name = azurerm_resource_group.vault.name
  sku                 = "Standard"

  frontend_ip_configuration {
   name                 = "PublicIPAddress"
   public_ip_address_id = azurerm_public_ip.vault.id
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  loadbalancer_id     = azurerm_lb.vault.id
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vault" {
  resource_group_name = azurerm_resource_group.vault.name
  loadbalancer_id     = azurerm_lb.vault.id
  name                = "vault-running-probe"
  port                = "8200"
}

resource "azurerm_lb_rule" "vault" {
   resource_group_name            = azurerm_resource_group.vault.name
   loadbalancer_id                = azurerm_lb.vault.id
   name                           = "vault"
   protocol                       = "Tcp"
   frontend_port                  = "8200"
   backend_port                   = "8200"
   backend_address_pool_id        = azurerm_lb_backend_address_pool.bpepool.id
   frontend_ip_configuration_name = "PublicIPAddress"
   probe_id                       = azurerm_lb_probe.vault.id
}

resource "azurerm_lb_nat_pool" "ssh" {
  resource_group_name            = azurerm_resource_group.vault.name
  name                           = "ssh"
  loadbalancer_id                = azurerm_lb.vault.id
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50099
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}
