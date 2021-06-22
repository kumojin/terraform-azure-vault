resource "azurerm_public_ip" "nginx" {
  name                  = "nginx-public-ip"
  location              = var.location
  resource_group_name   = azurerm_resource_group.vault.name
  allocation_method     = "Static"
  sku                   = "Standard"
}

resource "azurerm_subnet" "nginx" {
  name                 = "nginx-subnet"
  resource_group_name  = azurerm_resource_group.vault.name
  virtual_network_name = azurerm_virtual_network.vault.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_network_interface" "nginx_cert" {
  name                = "nginx-cert-nic"
  resource_group_name = azurerm_resource_group.vault.name
  location            = azurerm_resource_group.vault.location

  ip_configuration {
    name                          = "internal"
    public_ip_address_id          = azurerm_public_ip.nginx.id
    subnet_id                     = azurerm_subnet.nginx.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_security_group" "nginx" {
  name                = "nginx-nsg"
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
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "certbot"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nginx" {
  subnet_id                 = azurerm_subnet.nginx.id
  network_security_group_id = azurerm_network_security_group.nginx.id
}

data "template_file" "nginx_setup" {
  template = file("${path.module}/nginx-setup.tpl")

  vars = {
    cert_domain_name = var.cert_domain_name
    vault_ip_addr    = azurerm_public_ip.vault.ip_address
  }
}

resource "azurerm_linux_virtual_machine" "nginx_cert" {
  name                = "nginx-cert-vm"
  resource_group_name = azurerm_resource_group.vault.name
  location            = azurerm_resource_group.vault.location
  size                = var.nginx_vm_size
  custom_data         = base64encode(data.template_file.nginx_setup.rendered)

  network_interface_ids = [
    azurerm_network_interface.nginx_cert.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_id = var.nginx_source_image_id

  admin_username = var.nginx_vm_admin_user
  admin_ssh_key {
    username   = var.nginx_vm_admin_user
    public_key = file(var.nginx_vm_admin_ssh_key_path)
  }
}
