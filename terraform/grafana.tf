# Azure Managed Grafana. The Azure Monitor data source ships preconfigured in
# Managed Grafana; what actually makes it work is the role assignment below,
# which lets Grafana's managed identity read metrics and run log queries.

resource "azurerm_dashboard_grafana" "main" {
  name                  = "amg-${var.project_name}-${local.suffix}"
  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  grafana_major_version = var.grafana_major_version
  sku                   = "Standard"

  # Managed identity is the whole point: no data source credentials to rotate.
  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# Monitoring Reader on the resource group covers the Application Insights
# component, the Log Analytics workspace, and the Container App metrics.
# Scope it to the subscription instead if Grafana should see other workloads.
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id
}

# Log Analytics Reader is needed on top of Monitoring Reader for the Logs
# (KQL) query type used by the latency and custom metric panels.
resource "azurerm_role_assignment" "grafana_log_reader" {
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_dashboard_grafana.main.identity[0].principal_id
}

# Whoever runs terraform apply gets Grafana Admin so they can import the
# dashboard JSON from dashboards/ immediately after deploy.
resource "azurerm_role_assignment" "deployer_grafana_admin" {
  scope                = azurerm_dashboard_grafana.main.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
