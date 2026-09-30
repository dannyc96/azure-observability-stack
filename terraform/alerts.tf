# Alerting as code. Philosophy (expanded in the README): alert on symptoms
# users feel (errors, latency, availability), route everything through one
# action group, and make every alert actionable. No CPU alerts here on
# purpose: high CPU with healthy latency and error rate is not an incident.

# ---------------------------------------------------------------------------
# Action group: single fan-out point for every alert in the stack.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "oncall" {
  name                = "ag-${var.project_name}-oncall"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "oncall" # 12-char limit, shows up in SMS/push
  tags                = local.tags

  # Teams and Slack both accept plain incoming-webhook posts of the Azure
  # Monitor common alert schema (Teams via a Workflows/Logic Apps webhook,
  # Slack via an incoming webhook plus a small transform). The URL is a
  # sensitive variable so it never lands in the repo.
  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_url != "" ? [1] : []
    content {
      name                    = "chatops"
      service_uri             = var.alert_webhook_url
      use_common_alert_schema = true
    }
  }

  dynamic "email_receiver" {
    for_each = var.alert_email != "" ? [1] : []
    content {
      name                    = "oncall-email"
      email_address           = var.alert_email
      use_common_alert_schema = true
    }
  }
}

# ---------------------------------------------------------------------------
# 1) Request failure rate (symptom: users are getting errors)
#
# This is a log alert rather than a metric alert because Azure Monitor metric
# alerts cannot express a ratio (failed / total). A raw failed-request count
# threshold pages at high traffic and sleeps through outages at low traffic;
# a percentage does the right thing at any volume.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failure_rate" {
  name                = "alert-${var.project_name}-failure-rate"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  description         = "Server request failure rate above ${var.failure_rate_threshold_percent}% over 5 minutes. Check recent deploys first, then dependency health in the failures blade."
  tags                = local.tags

  scopes               = [azurerm_application_insights.main.id]
  severity             = 1 # Sev1: users are actively failing, respond now
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    # Guard against divide-by-zero quiet windows; no traffic is not a failure.
    query = <<-QUERY
      requests
      | summarize total = count(), failed = countif(success == false) by bin(timestamp, 5m)
      | where total > 0
      | extend failure_rate = todouble(failed) * 100.0 / todouble(total)
      | project timestamp, failure_rate
    QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "failure_rate"
    operator                = "GreaterThan"
    threshold               = var.failure_rate_threshold_percent

    # One bad 5-minute window fires. For noisier services, widen to 2 of 3
    # windows instead of raising the threshold: it keeps sensitivity to real
    # sustained failure while ignoring single-window blips.
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  auto_mitigation_enabled = true # resolve automatically when the rate recovers

  action {
    action_groups = [azurerm_monitor_action_group.oncall.id]
  }
}

# ---------------------------------------------------------------------------
# 2) p95 server response time (symptom: the service feels slow)
#
# Also a log alert: metric alert aggregations stop at avg/min/max, and
# averages hide tail latency, which is what users actually experience.
# p95 at 1000 ms default: an interactive API with a one-second p95 is
# already degrading, well before timeouts start.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "p95_latency" {
  name                = "alert-${var.project_name}-p95-latency"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  description         = "p95 server response time above ${var.p95_latency_threshold_ms} ms over 5 minutes. Check the performance blade for the slow operation, then downstream dependency latency."
  tags                = local.tags

  scopes               = [azurerm_application_insights.main.id]
  severity             = 2 # Sev2: degraded, not down; urgent but not a page-at-3am
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query = <<-QUERY
      requests
      | where success == true
      | summarize p95_ms = percentile(duration, 95) by bin(timestamp, 5m)
      | project timestamp, p95_ms
    QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "p95_ms"
    operator                = "GreaterThan"
    threshold               = var.p95_latency_threshold_ms

    # Latency needs two consecutive bad windows before firing: a single slow
    # window is usually a cold start or a burst, and paging on it trains
    # people to ignore the alert.
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 2
      number_of_evaluation_periods             = 2
    }
  }

  auto_mitigation_enabled = true

  action {
    action_groups = [azurerm_monitor_action_group.oncall.id]
  }
}

# ---------------------------------------------------------------------------
# 3) Availability (symptom: the service is unreachable from outside)
#
# A standard web test pings /healthz from multiple Azure regions every five
# minutes. This catches the failure modes in-process telemetry cannot see:
# DNS, TLS, ingress, or the app simply not running.
# ---------------------------------------------------------------------------
resource "azurerm_application_insights_standard_web_test" "healthz" {
  name                    = "webtest-${var.project_name}-healthz"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  application_insights_id = azurerm_application_insights.main.id
  description             = "URL ping against the orders API health endpoint."
  tags                    = local.tags

  # Five regions so a single probe location having a bad day cannot fire the
  # alert on its own (the alert needs 3 failed locations).
  geo_locations = [
    "us-va-ash-azr",   # East US
    "us-il-ch1-azr",   # North Central US
    "us-tx-sn1-azr",   # South Central US
    "emea-nl-ams-azr", # West Europe
    "apac-sg-sin-azr", # Southeast Asia
  ]

  frequency     = 300
  timeout       = 30
  enabled       = true
  retry_enabled = true # one transient network blip per probe does not count

  request {
    url = "https://${azurerm_container_app.orders_api.ingress[0].fqdn}/healthz"
  }

  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  name                = "alert-${var.project_name}-availability"
  resource_group_name = azurerm_resource_group.main.name
  description         = "Health endpoint unreachable from 3+ probe regions. Treat as an outage: check Container App revisions and ingress before anything else."
  tags                = local.tags

  scopes = [
    azurerm_application_insights_standard_web_test.healthz.id,
    azurerm_application_insights.main.id,
  ]

  severity    = 0 # Sev0: hard down from the user's point of view
  frequency   = "PT1M"
  window_size = "PT5M"

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.healthz.id
    component_id          = azurerm_application_insights.main.id
    failed_location_count = 3 # 3 of 5 regions failing rules out probe-side noise
  }

  action {
    action_group_id = azurerm_monitor_action_group.oncall.id
  }
}
