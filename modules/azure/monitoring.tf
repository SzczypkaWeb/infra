# Availability monitoring for both Static Web Apps, alerting to email.
# GCP's equivalent (uptime check, alerting to Slack) lives in
# ../gcp/monitoring.tf - Azure gets email instead of Slack because Azure
# Monitor has no native Slack action (only a raw webhook, which would need a
# relay to reformat the payload into what Slack's incoming webhook expects -
# not worth the extra infra for a portfolio project). See RUNBOOK.md section
# 9 for the full reasoning.
#
# Standard web tests (not the older "URL ping test" kind) - URL ping tests
# are being retired by Microsoft on 2026-09-30, so Standard is the only
# option worth adopting now anyway.

resource "azurerm_application_insights" "frontend" {
  name                = "frontend-availability"
  resource_group_name = azurerm_resource_group.frontend.name
  location            = azurerm_resource_group.frontend.location
  application_type    = "web"
}

resource "azurerm_application_insights_standard_web_test" "react_app" {
  name                    = "react-app-availability"
  resource_group_name     = azurerm_resource_group.frontend.name
  location                = azurerm_resource_group.frontend.location
  application_insights_id = azurerm_application_insights.frontend.id
  geo_locations           = ["us-tx-sn1-azr", "us-il-ch1-azr"]
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true

  request {
    url = "https://${azurerm_static_web_app.react_app.default_host_name}"
  }
}

resource "azurerm_application_insights_standard_web_test" "frontend_shell" {
  name                    = "frontend-shell-availability"
  resource_group_name     = azurerm_resource_group.frontend.name
  location                = azurerm_resource_group.frontend.location
  application_insights_id = azurerm_application_insights.frontend.id
  geo_locations           = ["us-tx-sn1-azr", "us-il-ch1-azr"]
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true

  request {
    url = "https://${azurerm_static_web_app.frontend_shell.default_host_name}"
  }
}

resource "azurerm_monitor_action_group" "email_alerts" {
  name                = "email-alerts"
  resource_group_name = azurerm_resource_group.frontend.name
  short_name          = "emailalert"

  email_receiver {
    name                    = "primary"
    email_address           = "p.szczypka.dev@gmail.com"
    use_common_alert_schema = true
  }
}

# One alert covering both web tests - fires whenever average availability
# drops below 100% for either, scoped to the whole Application Insights
# resource rather than filtered per-test (simpler, and there are only two
# tests to begin with).
resource "azurerm_monitor_metric_alert" "availability" {
  name                = "frontend-availability-alert"
  resource_group_name = azurerm_resource_group.frontend.name
  scopes              = [azurerm_application_insights.frontend.id]
  description         = "Fires when a Static Web App availability test fails."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.email_alerts.id
  }
}
