# Sample workload: the instrumented orders API running on Azure Container
# Apps (Consumption plan). The app is the telemetry source that makes the
# dashboards and alerts demonstrable.

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${local.suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

resource "azurerm_container_app" "orders_api" {
  name                         = "ca-orders-api"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.tags

  # The connection string is a secret at the platform level so it never shows
  # up in plain text on the revision spec.
  secret {
    name  = "appinsights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "orders-api"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }

      env {
        name  = "OTEL_SERVICE_NAME"
        value = "orders-api"
      }

      liveness_probe {
        path             = "/healthz"
        port             = 8000
        transport        = "HTTP"
        initial_delay    = 5
        interval_seconds = 10
      }

      readiness_probe {
        path             = "/healthz"
        port             = 8000
        transport        = "HTTP"
        interval_seconds = 10
      }
    }

    http_scale_rule {
      name                = "http-rps"
      concurrent_requests = 50
    }
  }
}
