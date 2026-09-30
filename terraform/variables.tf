variable "project_name" {
  description = "Short name used as a prefix for all resources. Lowercase letters and digits only, keeps generated names DNS-safe."
  type        = string
  default     = "obsstack"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,15}$", var.project_name))
    error_message = "project_name must be 3-16 chars, lowercase letters and digits, starting with a letter."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment tag (demo, dev, prod). Drives tagging only in this flat demo module."
  type        = string
  default     = "demo"
}

variable "container_image" {
  description = <<-EOT
    Fully qualified image reference for the orders API, e.g.
    ghcr.io/dannyc96/orders-api:latest or <acr>.azurecr.io/orders-api:v1.
    Build it with `make build-image` and push to any registry the Container
    Apps environment can reach. Public ghcr images need no registry block;
    for a private ACR add a registry block with a managed identity.
  EOT
  type        = string
  default     = "ghcr.io/dannyc96/orders-api:latest"
}

variable "container_cpu" {
  description = "vCPU allocation for the app container. 0.25 is the smallest Consumption tier slice and plenty for a demo."
  type        = number
  default     = 0.25
}

variable "container_memory" {
  description = "Memory allocation for the app container. Must pair with the CPU value per Container Apps sizing rules."
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  description = "Minimum replica count. 1 keeps the availability test green; 0 would scale to zero and fail the ping between requests."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum replica count for HTTP autoscaling."
  type        = number
  default     = 3
}

variable "log_retention_days" {
  description = "Log Analytics retention. 30 days is the free-included window; raise for real workloads with compliance needs."
  type        = number
  default     = 30
}

variable "alert_webhook_url" {
  description = "Incoming webhook URL for alert notifications (Teams or Slack). Sensitive: pass via TF_VAR_alert_webhook_url or a tfvars file kept out of git."
  type        = string
  sensitive   = true
  default     = ""
}

variable "alert_email" {
  description = "Optional email receiver for the action group. Empty string disables it."
  type        = string
  default     = ""
}

variable "failure_rate_threshold_percent" {
  description = <<-EOT
    Alert when the 5-minute request failure rate exceeds this percentage.
    5% is a deliberate starting point: low enough to catch real incidents,
    high enough that a single failed request during quiet traffic does not
    page anyone. Tune against your real traffic volume and SLO.
  EOT
  type        = number
  default     = 5
}

variable "p95_latency_threshold_ms" {
  description = <<-EOT
    Alert when p95 server response time exceeds this many milliseconds over
    5 minutes. 1000 ms assumes an interactive API where a one-second p95 is
    already user-visible pain. Set from your latency SLO, not from what the
    service happens to do today.
  EOT
  type        = number
  default     = 1000
}

variable "grafana_major_version" {
  description = "Azure Managed Grafana major version."
  type        = string
  default     = "11"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}
