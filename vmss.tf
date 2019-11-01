resource "azurerm_resource_group" "vmssrg" {
  name     = "vmssipssoncrg"
  location = "Central US"
}

resource "azurerm_virtual_network" "vmssvnet" {
  name                = "acctvn"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.vmssrg.location}"
  resource_group_name = "${azurerm_resource_group.vmssrg.name}"
}

resource "azurerm_subnet" "vmsssub" {
  name                 = "acctsub"
  resource_group_name  = "${azurerm_resource_group.vmssrg.name}"
  virtual_network_name = "${azurerm_virtual_network.vmssvnet.name}"
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_public_ip" "vmsslbip" {
  name                = "vmsslbip"
  location            = "${azurerm_resource_group.vmssrg.location}"
  resource_group_name = "${azurerm_resource_group.vmssrg.name}"
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${azurerm_resource_group.vmssrg.name}"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_lb" "vmsslb" {
  name                = "vmsslb"
  location            = "${azurerm_resource_group.vmssrg.location}"
  resource_group_name = "${azurerm_resource_group.vmssrg.name}"
  sku                 = "Standard"
  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = "${azurerm_public_ip.vmsslbip.id}"
  }
}

resource "azurerm_lb_rule" "lb8080" {
  resource_group_name            = "${azurerm_resource_group.vmssrg.name}"
  loadbalancer_id                = "${azurerm_lb.vmsslb.id}"
  name                           = "lbrule8080"
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.bpepool.id}"
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = "${azurerm_lb_probe.vmsslbprobe.id}"
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = "${azurerm_resource_group.vmssrg.name}"
  loadbalancer_id     = "${azurerm_lb.vmsslb.id}"
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_nat_pool" "lbnatpool" {
  resource_group_name            = "${azurerm_resource_group.vmssrg.name}"
  name                           = "ssh"
  loadbalancer_id                = "${azurerm_lb.vmsslb.id}"
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_probe" "vmsslbprobe" {
  resource_group_name = "${azurerm_resource_group.vmssrg.name}"
  loadbalancer_id     = "${azurerm_lb.vmsslb.id}"
  name                = "http-probe"
  protocol            = "Http"
  request_path        = "/health"
  port                = 8080
}

resource "azurerm_virtual_machine_scale_set" "test" {
  name                = "mytestscaleset-1"
  location            = "${azurerm_resource_group.vmssrg.location}"
  resource_group_name = "${azurerm_resource_group.vmssrg.name}"
  depends_on = [
        azurerm_lb_rule.lb8080
      ]
  # automatic rolling upgrade
  automatic_os_upgrade = true
  upgrade_policy_mode  = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 5
    pause_time_between_batches              = "PT0S"
  }

  # required when using rolling upgrade policy
  health_probe_id = "${azurerm_lb_probe.vmsslbprobe.id}"
  zones           = [1,2,3]
  sku {
    name     = "Standard_F2"
    tier     = "Standard"
    capacity = 9
  }
   
  
  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }

  os_profile {
    computer_name_prefix = "testvm"
    admin_username       = "myadmin"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/myadmin/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/demo_key.pub")}"
    }
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "vmssIPConfiguration"
      primary                                = true
      subnet_id                              = "${azurerm_subnet.vmsssub.id}"
      load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.bpepool.id}"]
      load_balancer_inbound_nat_rules_ids    = ["${azurerm_lb_nat_pool.lbnatpool.id}"]
    }
  }

  tags = {
    environment = "staging"
  }
}