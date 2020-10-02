# Configure the Azure Provider
provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  version = "=2.20.0"
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "terraform" {
  name     = "${var.resource_prefix}-rg"
  location = "${var.location}"
}

# Create a virtual network within the resource group
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_prefix}-vnet"
  resource_group_name = "${azurerm_resource_group.terraform.name}"
  location            = "${var.location}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "public_sub_net" {
  name                 = "${var.resource_prefix}-public-subnet"
  resource_group_name  = "${azurerm_resource_group.terraform.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefixes     = ["10.0.1.0/24"]
}

# Create network security group and SSH rule for public subnet.
resource "azurerm_network_security_group" "public_nsg" {
  name                = "${var.resource_prefix}-pblc-nsg"
  resource_group_name = "${azurerm_resource_group.terraform.name}"
  location            = "${var.location}"

  # Allow SSH traffic in from Internet to public subnet.
  security_rule {
    name                       = "allow-ssh-all"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

# Associate network security group with public subnet.
resource "azurerm_subnet_network_security_group_association" "public_subnet_assoc" {
  subnet_id                 = "${azurerm_subnet.public_sub_net.id}"
  network_security_group_id = "${azurerm_network_security_group.public_nsg.id}"
}

resource "azurerm_public_ip" "public_ip" {
  name                = "${var.resource_prefix}-public-ip"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.terraform.name}"
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "bastion_nic" {
  name                      = "${var.resource_prefix}-bstn-nic"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.terraform.name}"

  ip_configuration {
    name                          = "${var.resource_prefix}-bstn-nic-cfg"
    subnet_id                     = "${azurerm_subnet.public_sub_net.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.public_ip.id}"
  }
}

resource "azurerm_network_interface_security_group_association" "pub_nsg_nic_association" {
  network_interface_id      = "${azurerm_network_interface.bastion_nic.id}"
  network_security_group_id = "${azurerm_network_security_group.public_nsg.id}"
}

resource "azurerm_subnet" "private_sub_net" {
  name                 = "${var.resource_prefix}-private-subnet"
  resource_group_name  = "${azurerm_resource_group.terraform.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "private_nsg" {
  name                = "${var.resource_prefix}-prvt-nsg"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.terraform.name}"

  # Allow SSH traffic in from public subnet to private subnet.
  security_rule {
    name                       = "allow-ssh-public-subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  # Block all outbound traffic from private subnet to Internet.
  security_rule {
    name                       = "deny-internet-all"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_subnet_assoc" {
  subnet_id                 = "${azurerm_subnet.private_sub_net.id}"
  network_security_group_id = "${azurerm_network_security_group.private_nsg.id}"
}

# Create network interface for worker host VM in private subnet.
resource "azurerm_network_interface" "worker_nic" {
  name                      = "${var.resource_prefix}-wrkr-nic"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.terraform.name}"

  ip_configuration {
    name                          = "${var.resource_prefix}-wrkr-nic-cfg"
    subnet_id                     = "${azurerm_subnet.private_sub_net.id}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "pri_nsg_nic_association" {
  network_interface_id      = "${azurerm_network_interface.worker_nic.id}"
  network_security_group_id = "${azurerm_network_security_group.private_nsg.id}"
}

resource "random_id" "random_id" {
  keepers = {
    resource_group = "${azurerm_resource_group.terraform.name}"
  }
  byte_length = 8
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "diag${random_id.random_id.hex}"
  resource_group_name      = "${azurerm_resource_group.terraform.name}"
  location                 = "${var.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create bastion host VM.
resource "azurerm_virtual_machine" "bastion_vm" {
  name                  = "${var.resource_prefix}-bstn-vm001"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.terraform.name}"
  network_interface_ids = ["${azurerm_network_interface.bastion_nic.id}"]
  vm_size               = "Standard_DS1_v2"

  storage_os_disk {
    name              = "${var.resource_prefix}-bstn-dsk001"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "${var.resource_prefix}-bstn-vm001"
    admin_username = "${var.username}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    # Bastion host VM public key.
    ssh_keys {
      path     = "/home/${var.username}/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCuNE5mC3TUOoA98ZjOUhf98lVwmVbD7FbCLbQA7RyneTR8vq1D/0FjOkofVQAMfhlxN+CLhZLKknSC5ksUbACXCnVnNOwmneJyQ+oGCJfQPssAY+0/EL4mloOoguuue42dvHhx38SPDD7JDEL8O5OJ9fbaTvAMgDZfj3wQWO27tWpjSkVOoPEEkVoRRws9VmwuzObKD1BGZ0vM2TpSogorGCcpDsPNfDgCpJBcNzbpCvy0muPdcvMREC0n3KIU7D+LN4gotcXO+HuPVSfB1QKLXrhufF13tu4Tl93yoFWnmdupOt2SwyY7HMpT6d66X03X4dv6jJoL01nSVlnaQ0yNdl8h0t5iZm3crIKQ1kZAlYwY+qU7Lk/kVFpRLb67uk0br9gEEmzzGCoCXLi8yY2mmFyJba/bjkEjV4X/TIwRpVHzzIMw9ukm05BRY5JP+KGr2/KgWDLFUwxsYvEe5Wxa0a4cfjyUa/d+DVoO2RHOx1w8BtHcpTNPHgRY7Ix3LwrpODc3EwSRBKJ6kJIjAnbt65pyjqKLZ5iQO9TmZ3mgJ4nQZweE0lOY8jaCXdbVpzd4ZefAWLsnnzU3FU0MUltE0HcBiJkrg9Ey16Qko8a0Gh7XW5D/WU2yezFQj2Lz5jaheGtaXROnQ4YHQjId24jB9hOvhMDWcUSNibl8OOJXbQ=="
    }
  }

  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${azurerm_storage_account.storage_account.primary_blob_endpoint}"
  }
}

# Create worker host VM.
resource "azurerm_virtual_machine" "worker_vm" {
  name                  = "${var.resource_prefix}-wrkr-vm001"
  location              = "${var.location}"
  resource_group_name   = "${azurerm_resource_group.terraform.name}"
  network_interface_ids = ["${azurerm_network_interface.worker_nic.id}"]
  vm_size               = "Standard_DS1_v2"

  storage_os_disk {
    name              = "${var.resource_prefix}-wrkr-dsk001"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "${var.resource_prefix}-wrkr-vm001"
    admin_username = "${var.username}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    # Worker host VM public key.
    ssh_keys {
      path     = "/home/${var.username}/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCuNE5mC3TUOoA98ZjOUhf98lVwmVbD7FbCLbQA7RyneTR8vq1D/0FjOkofVQAMfhlxN+CLhZLKknSC5ksUbACXCnVnNOwmneJyQ+oGCJfQPssAY+0/EL4mloOoguuue42dvHhx38SPDD7JDEL8O5OJ9fbaTvAMgDZfj3wQWO27tWpjSkVOoPEEkVoRRws9VmwuzObKD1BGZ0vM2TpSogorGCcpDsPNfDgCpJBcNzbpCvy0muPdcvMREC0n3KIU7D+LN4gotcXO+HuPVSfB1QKLXrhufF13tu4Tl93yoFWnmdupOt2SwyY7HMpT6d66X03X4dv6jJoL01nSVlnaQ0yNdl8h0t5iZm3crIKQ1kZAlYwY+qU7Lk/kVFpRLb67uk0br9gEEmzzGCoCXLi8yY2mmFyJba/bjkEjV4X/TIwRpVHzzIMw9ukm05BRY5JP+KGr2/KgWDLFUwxsYvEe5Wxa0a4cfjyUa/d+DVoO2RHOx1w8BtHcpTNPHgRY7Ix3LwrpODc3EwSRBKJ6kJIjAnbt65pyjqKLZ5iQO9TmZ3mgJ4nQZweE0lOY8jaCXdbVpzd4ZefAWLsnnzU3FU0MUltE0HcBiJkrg9Ey16Qko8a0Gh7XW5D/WU2yezFQj2Lz5jaheGtaXROnQ4YHQjId24jB9hOvhMDWcUSNibl8OOJXbQ=="
    }
  }

  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${azurerm_storage_account.storage_account.primary_blob_endpoint}"
  }
}

# IP addresses of public IP addresses provisioned.
output "public_ip_addresses" {
  description = "IP addresses of public IP addresses provisioned."
  value       = "${azurerm_public_ip.public_ip.*.ip_address}"
}

# IP addresses of private IP addresses provisioned.
output "private_ip_addresses" {
  description = "IP addresses of private IP addresses provisioned."
  value       = "${concat(azurerm_network_interface.bastion_nic.*.private_ip_address, azurerm_network_interface.worker_nic.*.private_ip_address)}"
}