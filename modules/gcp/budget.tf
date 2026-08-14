# Cost guardrail for the orchestrator platform work (see BLOG_NOTES.md /
# RUNBOOK.md) - alerts only, deliberately NOT an auto-stop/kill-switch.
# This billing account also covers the live backend Cloud Run service, so an
# automated "disable billing at 100%" mechanism could take down production
# by mistake - alerting loudly and deciding manually is the safer default.
#
# NOT CURRENTLY DEPLOYED: the google_billing_budget resource below fails
# with an unhelpful "Error 400: Request contains an invalid argument" on
# this account - confirmed via testing (quota project and API-enablement
# were both fixed first and it still failed) and corroborated externally:
# GCP Free Trial billing accounts don't support budget creation at all,
# since Google itself owns the billing account for the duration of the
# trial. No Terraform-side fix exists for this - it's a platform
# restriction, not a config bug. Practically lower-risk than it sounds: the
# trial has no payment method attached, so a runaway spend scenario ends in
# services being suspended once the trial credit is exhausted, not a
# surprise charge - the alert would have been a nicer early warning, not
# the only thing standing between "fine" and "billed."
#
# Revisit if this billing account ever moves off Free Trial status (e.g. a
# payment method gets added) - re-enable by uncommenting below, no other
# changes needed.
#
# data "google_project" "current" {
#   project_id = "szczypka-web-backend"
# }
#
# resource "google_billing_budget" "orchestrator_guardrail" {
#   billing_account = "01EEF1-ED3C6C-C0FB78"
#   display_name    = "orchestrator-platform-guardrail"
#
#   budget_filter {
#     projects = ["projects/${data.google_project.current.number}"]
#   }
#
#   amount {
#     specified_amount {
#       currency_code = "USD"
#       units         = "25"
#     }
#   }
#
#   threshold_rules {
#     threshold_percent = 0.5
#   }
#   threshold_rules {
#     threshold_percent = 0.8
#   }
#   threshold_rules {
#     threshold_percent = 1.0
#   }
#
#   all_updates_rule {
#     monitoring_notification_channels = [google_monitoring_notification_channel.slack_alerts.id]
#   }
# }
