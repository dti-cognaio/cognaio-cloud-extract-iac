terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
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
  subscription_id = var.subscription_id
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location =  var.default_location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${azurerm_resource_group.rg.name}-vnet-idp"
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
  count = var.deploy_openai_services ? 1 : 0
  name                = "${azurerm_resource_group.rg.name}-ai-service"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "CognitiveServices"
  sku_name            = "S0"
}

resource "azurerm_cognitive_account" "openai" {
  count = var.deploy_openai_services ? 1 : 0
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

resource "azurerm_cognitive_deployment" "deployment_gpt" {
  count = var.deploy_openai_services ? 1 : 0
  name                 = "gpt-4.1"
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = "gpt-4.1"
    version = "2025-04-14"
  }

  sku {
    name = "GlobalStandard"
    capacity = 5
  }
}

resource "azurerm_cognitive_deployment" "deployment_gpt_mini" {
  count = var.deploy_openai_services ? 1 : 0
  name                 = "gpt-4.1-mini"
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = "gpt-4.1-mini"
    version = "2025-04-14"
  }

  sku {
    name = "GlobalStandard"
    capacity = 5
  }
}

resource "azurerm_cognitive_deployment" "deployment_embedding_3_large" {
  count = var.deploy_openai_services ? 1 : 0
  name                 = "text-embedding-3-large"
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = "text-embedding-3-large"
    version = "1"
  }

  sku {
    name = "Standard"
    capacity = 10
  }
}

resource "azurerm_cognitive_account" "formRecognizer" {
  count = var.deploy_openai_services ? 1 : 0
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
  count = var.deploy_key_vault ? 1 : 0
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
  resource_group_name = var.resource_group_name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Postgresql
resource "azurerm_private_dns_zone" "dns-zone" {
  count = var.deploy_postgresql ? 1 : 0
  name                = "${azurerm_resource_group.rg.name}.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql-network-link" {
  count = var.deploy_postgresql ? 1 : 0
  name                  = "psql-dns-zone-link"
  private_dns_zone_name = azurerm_private_dns_zone.dns-zone[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

resource "azurerm_postgresql_flexible_server" "sql-server" {
  count = var.deploy_postgresql ? 1 : 0
  name                   = "${azurerm_resource_group.rg.name}-sql"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "16"
  public_network_access_enabled = false
  delegated_subnet_id    = azurerm_subnet.subnet-resources.id
  private_dns_zone_id    = azurerm_private_dns_zone.dns-zone[0].id
  administrator_login    = var.psql_username
  administrator_password = var.psql_password
  zone                   = "1"

  storage_mb = 262144

  sku_name   = "B_Standard_B2ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.sql-network-link]
}

resource "azurerm_postgresql_flexible_server_configuration" "sql-config" {
  count = var.deploy_postgresql ? 1 : 0
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.sql-server[0].id
  value     = "CITEXT,PGCRYPTO,VECTOR,PG_TRGM,FUZZYSTRMATCH"
}

resource "azurerm_subnet" "subnet-aks" {
  count = var.deploy_aks ? 1 : 0
  name                 = "subnet-idp-aks-int"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.16.32.0/20"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  count = var.deploy_aks ? 1 : 0
  name                      = "${azurerm_resource_group.rg.name}-aks"
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name
  automatic_upgrade_channel = "patch"
  sku_tier                  = "Free"
  dns_prefix                = "${azurerm_resource_group.rg.name}-aks-dns"
  kubernetes_version        = "1.32.6"

  default_node_pool {
    name                         = "default"
    node_count                   = 2
    vm_size                      = var.deploy_aks_separated_work_system_node_pool ? "Standard_D2s_v3" : "Standard_D4s_v3"
    max_pods                     = 60
    vnet_subnet_id               = azurerm_subnet.subnet-aks[0].id
    only_critical_addons_enabled = var.deploy_aks_separated_work_system_node_pool ? true : false
    #zones           = ["1"] 

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
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
    tenant_id          = var.tenant_id
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "np_workload_1" {
  count = var.deploy_aks && var.deploy_aks_separated_work_system_node_pool ? 1 : 0
  name                  = "workload1"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks[0].id
  vm_size               = "Standard_D4s_v3"
  max_pods              = 60
  node_count            = 2
  vnet_subnet_id        = azurerm_subnet.subnet-aks[0].id
  mode                  = "User"
  #zones                = ["1"] 
}

resource "azurerm_role_assignment" "aks_to_registry_role"  {
  count = var.is_container_registry_internally && var.deploy_aks ? 1 : 0
  scope                = var.deploy_container_registry ? azurerm_container_registry.registry[count.index].id : data.azurerm_container_registry.registry[count.index].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks[0].kubelet_identity[0].object_id
}

resource "azurerm_public_ip" "pip" {
  count = var.deploy_public_ip ? 1 : 0
  name                = "${azurerm_resource_group.rg.name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  domain_name_label   = azurerm_resource_group.rg.name
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
    public_ip_address_id = azurerm_public_ip.pip[0].id
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
    policy_type          = "CustomV2"
    policy_name          = "AppGwSslPolicy20220101S"
    min_protocol_version = "TLSv1_3"
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