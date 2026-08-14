# Cost guardrail for the orchestrator platform work - see the matching
# comment in ../gcp/budget.tf for why this is alerting-only, no auto-stop
# (this subscription also runs the live Static Web Apps).
resource "azurerm_consumption_budget_subscription" "orchestrator_guardrail" {
  name            = "orchestrator-platform-guardrail"
  subscription_id = "/subscriptions/${local.subscription_id}"

  amount     = 25
  time_grain = "Monthly"

  time_period {
    # Consumption budgets require an explicit period - start of the current
    # month, running for ~2 years before needing a Terraform update to
    # extend it (Azure requires an end_date, unlike GCP's budget which is
    # open-ended by default).
    start_date = "2026-08-01T00:00:00Z"
    end_date   = "2028-08-01T00:00:00Z"
  }

  # Reuses the same email action group from monitoring.tf.
  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThanOrEqualTo"
    contact_groups = [azurerm_monitor_action_group.email_alerts.id]
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    contact_groups = [azurerm_monitor_action_group.email_alerts.id]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    contact_groups = [azurerm_monitor_action_group.email_alerts.id]
  }
}
