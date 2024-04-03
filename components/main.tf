terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
  # backend "azurerm" {
  #   resource_group_name  = "dti-de-devops"
  #   storage_account_name = "dtidedevopssa"
  #   container_name       = "idp-int-components-tfstate"
  #   key                  = "terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = var.ressource_group_name
  location =  var.default_location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-idp"
  address_space       = ["172.16.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet-gw" {
  count = var.deploy_application_gateway ? 1 : 0
  name                 = "subnet-idp-gw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.16.0.0/23"]
}

resource "azurerm_subnet" "subnet-resources" {
  name                 = "subnet-idp-resources"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.16.4.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_cognitive_account" "ai-service" {
  name                = "${azurerm_resource_group.rg.name}-ai-service"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "CognitiveServices"
  sku_name            = "S0"
}

resource "azurerm_cognitive_account" "openai" {
  name                  = "${azurerm_resource_group.rg.name}-openai"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = var.openAi_location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "${azurerm_resource_group.rg.name}-openai"

  network_acls {
    default_action = "Allow"
  }
}

resource "azurerm_cognitive_deployment" "deployment_gpt35_turbo" {
  name                 = "gpt-35-turbo"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  rai_policy_name      = "UserPromtsDisableContentFilter"
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo"
    version = "0613"
  }

  scale {
    type = "Standard"
    capacity = 122
  }
}

resource "azurerm_cognitive_deployment" "deployment_gpt35_turbo_16k" {
  name                 = "gpt-35-turbo-16k"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  rai_policy_name      = "UserPromtsDisableContentFilter"
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo-16k"
    version = "0613"
  }

  scale {
    type = "Standard"
    capacity = 118
  }
}

resource "azurerm_cognitive_deployment" "deployment_embedding_ada_002" {
  name                 = "text-embedding-ada-002"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  rai_policy_name      = "UserPromtsDisableContentFilter"
  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = "2"
  }

  scale {
    type = "Standard"
    capacity = 30
  }
}

resource "azurerm_cognitive_account" "formRecognizer" {
  name                       = "${azurerm_resource_group.rg.name}-formRecognizer"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = var.openAi_location
  kind                       = "FormRecognizer"
  sku_name                   = "S0"
  custom_subdomain_name      = "${azurerm_resource_group.rg.name}-formrecognizer"
  dynamic_throttling_enabled = false
  fqdns                      = []

  network_acls {
    default_action = "Allow"
    ip_rules       = []
  }
}

# Azure Vault
resource "azurerm_key_vault" "av" {
  name                       = "${azurerm_resource_group.rg.name}-av"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  enable_rbac_authorization  = true
}

data "azurerm_container_registry" "registry" {
  count = !var.deploy_container_registry && var.is_container_registry_internally ? 1 : 0
  name                = var.container_registry_name
  resource_group_name = var.container_registry_resource_group_name
}

resource "azurerm_container_registry" "registry" {
  count = var.deploy_container_registry ? 1 : 0
  name                = var.container_registry_name
  resource_group_name = var.ressource_group_name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Postgresql
resource "azurerm_private_dns_zone" "dns-zone" {
  name                = "${azurerm_resource_group.rg.name}.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql-network-link" {
  name                  = "psql-dns-zone-link"
  private_dns_zone_name = azurerm_private_dns_zone.dns-zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

resource "azurerm_postgresql_flexible_server" "sql-server" {
  name                   = "${azurerm_resource_group.rg.name}-sql"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "14"
  delegated_subnet_id    = azurerm_subnet.subnet-resources.id
  private_dns_zone_id    = azurerm_private_dns_zone.dns-zone.id
  administrator_login    = var.psql_username
  administrator_password = var.psql_password
  zone                   = "1"

  storage_mb = 262144

  sku_name   = "B_Standard_B2ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.sql-network-link]
}

resource "azurerm_postgresql_flexible_server_configuration" "sql-config" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.sql-server.id
  value     = "CITEXT,PGCRYPTO,VECTOR"
}

resource "azurerm_subnet" "subnet-aks" {
  name                 = "subnet-idp-aks-int"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.16.32.0/20"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                      = "${azurerm_resource_group.rg.name}-aks"
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name
  automatic_channel_upgrade = "patch"
  sku_tier                  = "Free"
  dns_prefix                = "${azurerm_resource_group.rg.name}-aks-dns"
  kubernetes_version        = "1.26.10"

  default_node_pool {
    name                         = "default"
    node_count                   = 2
    vm_size                      = "Standard_D2s_v3"
    max_pods                     = 60
    vnet_subnet_id               = azurerm_subnet.subnet-aks.id
    only_critical_addons_enabled = true # supported
    #zones           = ["1"] 
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
  }

dynamic "ingress_application_gateway" {
    for_each = var.deploy_application_gateway ? [1] : []
    content {
      gateway_id = azurerm_application_gateway.gw[0].id
    }
  }
  # ingress_application_gateway {
  #   gateway_id = azurerm_application_gateway.gw[count.index].id
  # }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    managed            = true
    tenant_id          = "e0fb3e0c-cab1-4e3a-9aa8-f90bd991811b"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "np_workload_1" {
  name                  = "workload1"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_D4s_v3"
  max_pods              = 60
  node_count            = 2
  vnet_subnet_id        = azurerm_subnet.subnet-aks.id
  mode                  = "User"
  #zones                = ["1"] 
}

resource "azurerm_role_assignment" "aks_to_registry_role"  {
  count = var.is_container_registry_internally ? 1 : 0
  scope                = var.deploy_container_registry ? azurerm_container_registry.registry[count.index].id : data.azurerm_container_registry.registry[count.index].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

resource "azurerm_public_ip" "pip" {
  name                = "${azurerm_resource_group.rg.name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_web_application_firewall_policy" "fw-policy" {
  count = var.deploy_application_gateway ? 1 : 0
  name                = "${azurerm_resource_group.rg.name}-fw-policy"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  managed_rules {
    managed_rule_set {
      version = "3.2"
      rule_group_override {
        rule_group_name = "General"
      }
    }
  }
  policy_settings {
  }
}

resource "azurerm_application_gateway" "gw" {
  count = var.deploy_application_gateway ? 1 : 0
  name                = "${azurerm_resource_group.rg.name}-gw"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  firewall_policy_id  = azurerm_web_application_firewall_policy.fw-policy[count.index].id

  sku {
    capacity = 2
    name     = "WAF_v2"
    tier     = "WAF_v2"
  }

  backend_address_pool {
    name = "defaultaddresspool"
  }

  frontend_ip_configuration {
    name                 = "appGatewayFrontendIP"
    public_ip_address_id = azurerm_public_ip.pip.id
  }

  frontend_port {
    name = "appGatewayFrontendPort"
    port = 80
  }

  frontend_port {
    name = "fp-443"
    port = 443
  }

  backend_address_pool {
    name = "defaultaddresspool"
  }

  backend_http_settings {
    cookie_based_affinity = "Disabled"
    name                  = "defaulthttpsetting"
    port                  = 80
    probe_name            = "defaultprobe-Http"
    protocol              = "Http"
  }

  gateway_ip_configuration {
    name      = "appGatewayFrontendIP"
    subnet_id = azurerm_subnet.subnet-gw[count.index].id
  }

  http_listener {
    frontend_ip_configuration_name = "appGatewayFrontendIP"
    frontend_port_name             = "appGatewayFrontendPort"
    name                           = "fl-f6e923a52f57ad4b5d2f5981db0bd5be"
    protocol                       = "Http"
  }

  probe {
    host                = "localhost"
    interval            = 30
    name                = "defaultprobe-Http"
    path                = "/"
    protocol            = "Http"
    timeout             = 30
    unhealthy_threshold = 3
    match {
      status_code = []
    }
  }
  probe {
    host                = "localhost"
    interval            = 30
    name                = "defaultprobe-Https"
    path                = "/"
    protocol            = "Https"
    timeout             = 30
    unhealthy_threshold = 3
    match {
      status_code = []
    }
  }
  request_routing_rule {
    name                       = "rr-f6e923a52f57ad4b5d2f5981db0bd5be"
    rule_type                  = "Basic"
    http_listener_name         = "fl-f6e923a52f57ad4b5d2f5981db0bd5be"
    backend_address_pool_name  = "defaultaddresspool"
    backend_http_settings_name = "defaulthttpsetting"
    priority                   = 19005
  }

  ssl_policy {
    policy_type          = "Custom"
    policy_name          = "AppGwSslPolicy20220101S"
    min_protocol_version = "TLSv1_2"
    cipher_suites = [
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
      "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
      "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384"
    ]
  }

  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      redirect_configuration,
      request_routing_rule,
      ssl_certificate,
      tags,
      url_path_map,
      ssl_policy
    ]
  }
}