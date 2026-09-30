output "resource_group_name" {
  description = "Resource group containing the whole stack."
  value       = azurerm_resource_group.main.name
}

output "app_fqdn" {
  description = "Public FQDN of the orders API. Point generate-traffic.sh at https://<this>."
  value       = azurerm_container_app.orders_api.ingress[0].fqdn
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana URL. Sign in with your Entra identity; the deployer is granted Grafana Admin."
  value       = azurerm_dashboard_grafana.main.endpoint
}

output "log_analytics_workspace_id" {
  description = "Workspace resource ID, useful when wiring extra data sources or diagnostic settings."
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_connection_string" {
  description = "Connection string for running the app locally against the deployed telemetry backend."
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}
