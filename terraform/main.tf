# Core observability plumbing: resource group, Log Analytics workspace, and a
# workspace-based Application Insights component. Everything else in this
# module hangs off these three resources.
#
# This repo keeps a single flat root module on purpose: it is a demo you can
# read top to bottom. At scale the move is to extract modules (monitoring,
# app-platform, alerting) with typed inputs and publish them through a module
# registry; see the README.

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  suffix = random_string.suffix.result

  tags = merge(
    {
      project     = "azure-observability-stack"
      environment = var.environment
      managed_by  = "terraform"
      repo        = "github.com/dannyc96/azure-observability-stack"
    },
    var.tags,
  )
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = local.tags
}

# Single workspace for everything: Container Apps console logs, Application
# Insights telemetry, and the query surface Grafana and the alert rules share.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

# Workspace-based Application Insights (classic mode is deprecated). The
# OpenTelemetry distro in the app exports traces, metrics, and logs here via
# the connection string.
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.tags
}
