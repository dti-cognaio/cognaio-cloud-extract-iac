variable "tenant_id" {
  type     = string
  nullable = false
}

variable "subscription_id" {
  type     = string
  nullable = false
}

variable "resource_group_name" {
  default  = "ais-test-rg"
  type     = string
  nullable = false
}

variable "default_location" {
  default  = "switzerlandnorth"
  type     = string
  nullable = false
}

variable "openAi_location" {
  default  = "switzerlandnorth"
  type     = string
  nullable = false
}

variable "deploy_application_gateway" {
  default  = true
  type     = bool
  nullable = false
}

variable "deploy_openai_services" {
  default  = true
  type     = bool
  nullable = false
}

variable "deploy_postgresql" {
  default  = true
  type     = bool
  nullable = false
}

variable "deploy_public_ip" {
  default  = true
  type     = bool
  nullable = false
}

variable "deploy_aks" {
  default  = true
  type     = bool
  nullable = false
}

variable "deploy_aks_separated_work_system_node_pool" {
  default  = true
  type     = bool
  nullable = false
}

variable "deploy_key_vault" {
  default  = true
  type     = bool
  nullable = false
}

variable "deploy_container_registry" {
  default  = true
  type     = bool
  nullable = false
}

variable "is_container_registry_internally" {
  default  = true
  type     = bool
  nullable = false
}

variable "container_registry_name" {
  default  = "ais-test-cr"
  type     = string
  nullable = false
}

variable "container_registry_resource_group_name" {
  default  = "ais-test-rg"
  type     = string
  nullable = false
}

variable "psql_username" {
  type     = string
  nullable = false
}

variable "psql_password" {
  type      = string
  nullable  = false
  sensitive = true
}