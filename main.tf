provider "azurerm" {
  features {}
}

locals {
  //virtual_machine_name = "${var.prefix}-vm"
  admin_username       = random_string.admin_user.result
  admin_password       = random_password.password.result
  custom_data          = templatefile("${path.module}/files/setup.ps1", { 
                          cert = tls_self_signed_cert.example.cert_pem, 
                          privkey = tls_private_key.example.private_key_pem, pfxpass=random_password.pfxpass.result, 
                          rdp_port=var.rdp_port, 
                          winrm_port=var.winrm_port,
                          sshd_config=templatefile("${path.module}/files/sshd_config.tmpl", {sshd_port=var.sshd_port}),
                          sshd_port=var.sshd_port
                          stager=file("${path.module}/files/stager.ps1") 
                          } ) 
}

resource "random_string" "admin_user" {
  length = 7
  special = false
  number = false
  lower = false
}

resource "random_password" "password" {
  length = 16
  special = true
  override_special = "_%@"
}

resource "random_password" "pfxpass" {
  length = 16
  special = false
}

resource "tls_private_key" "example" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "example" {
  key_algorithm   = "ECDSA"
  is_ca_certificate = true
  private_key_pem = tls_private_key.example.private_key_pem

  subject {
    common_name  = "example.com"
    organization = "ACME Examples, Inc"
  }

  validity_period_hours = 12

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

}

resource "azurerm_resource_group" "example" {
  name     = "test-resources"
  location = "East US 2"
}

resource "azurerm_virtual_network" "example" {
  name                = "test-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "example" {
  name                 = "acctsub"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "example" {
  name                    = "test-pip"
  location                = azurerm_resource_group.example.location
  resource_group_name     = azurerm_resource_group.example.name
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30

  tags = {
    environment = "test"
  }
}

resource "azurerm_network_interface" "example" {
  name                = "test-nic"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.example.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.5"
    public_ip_address_id          = azurerm_public_ip.example.id
  }
}

resource "azurerm_windows_virtual_machine" "example" {
  name                      = "test-vm"
  location                  = azurerm_resource_group.example.location
  resource_group_name       = azurerm_resource_group.example.name
  size                      = "Standard_B2s"
  admin_username            = local.admin_username
  admin_password            = local.admin_password
  network_interface_ids     = [azurerm_network_interface.example.id]
  enable_automatic_updates  = true 
  custom_data               = base64encode(local.custom_data)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # az vm image list -f "Windows-10" --all -otable
  # windows 10 1909 professional
  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-10"
    sku       = "19h2-pro-g2"
    version   = "latest"
  }

  additional_unattend_content {
    setting = "AutoLogon"
    content = "<AutoLogon><Password><Value>${local.admin_password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${local.admin_username}</Username></AutoLogon>"
  }

  additional_unattend_content {
    setting = "FirstLogonCommands"
    content = file("./files/FirstLogonCommands.xml")
  }

  provisioner "remote-exec" {
    connection {
      type     = "winrm"
      user     = local.admin_username
      password = local.admin_password
      host     = self.public_ip_address
      port     = var.winrm_port
      https    = true
      timeout  = "10m"

      # NOTE: if you're using a real certificate, rather than a self-signed one, you'll want this set to `false`/to remove this.
      insecure = true
    }

    inline = [
      "cd C:\\terraform",
      "type nul > success.txt",
    ]
  }

}

resource "azurerm_network_security_group" "example" {
  name                = "acceptanceTestSecurityGroup1"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  security_rule {
    name                       = "yolo_rdp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.rdp_port
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "yolo_outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "yolo_winrm"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.winrm_port
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "yolo_frida-server"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6345"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "yolo_sshd"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.sshd_port
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "local_file" "rdp_connection" {
    content     = templatefile("${path.module}/files/rdp.tmpl", {
                    public_ip=data.azurerm_public_ip.example.ip_address, 
                    port=var.rdp_port, 
                    admin=local.admin_username
                    })
    filename = "${path.module}/connection.rdp"
}

data "azurerm_public_ip" "example" {
  name                = azurerm_public_ip.example.name
  resource_group_name = azurerm_windows_virtual_machine.example.resource_group_name
}

output "setup_script" {
  value = local.custom_data
}

output "public_ip_address" {
  value = data.azurerm_public_ip.example.ip_address
}

output "adminuser_cred" {
  value = local.admin_password
}

output "adminuser" {
  value = local.admin_username
}