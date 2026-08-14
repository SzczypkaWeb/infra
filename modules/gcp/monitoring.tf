# Uptime/availability monitoring for the backend Cloud Run service, alerting
# to Slack. Azure's equivalent (Application Insights availability tests,
# alerting to email instead - no native Slack action exists there) lives in
# ../azure/monitoring.tf. See RUNBOOK.md section 9 for why the two clouds use
# different alert channels.

# The Slack notification channel is deliberately NOT created by this resource
# block from scratch - google_monitoring_notification_channel with
# type = "slack" + sensitive_labels.auth_token is a known-broken path
# (https://github.com/hashicorp/terraform-provider-google/issues/11346):
# channels created this way silently never actually deliver a Slack message,
# even though `terraform apply` succeeds and the channel shows up in the
# Console. Real Slack delivery only works for channels created through the
# Console's own "Add new" -> Slack -> OAuth flow (Monitoring -> Alerting ->
# Edit Notification Channels), which links the workspace directly rather than
# minting a bot token you paste in - same reasoning Google gives internally
# (b/275101438, referenced in the issue above).
#
# So: this channel is bootstrapped out-of-band once via the Console (see
# RUNBOOK.md for the exact steps), then imported here - same
# create-manually-then-import pattern already used for the GCS state bucket
# and the storage account in the Azure module. `import.sh` has the import
# line; find the real channel ID via:
#   gcloud alpha monitoring channels list --project=szczypka-web-backend
resource "google_monitoring_notification_channel" "slack_alerts" {
  # Matches the real display name set when linking via the Console (Slack ->
  # Add new) - kept in sync deliberately, unlike labels/sensitive_labels
  # below, since this field IS visible/comparable and a mismatch here would
  # cause a pointless rename on every future plan.
  display_name = "GCP alert"
  type          = "slack"
  labels = {
    channel_name = "#alerts"
  }

  # The real channel already carries Google-managed OAuth credentials that
  # aren't exposed back to us (and can't be re-derived from a `labels` diff) -
  # without this, every plan after import would show a permanent diff trying
  # to "fix" fields Terraform can't actually see the real value of.
  lifecycle {
    ignore_changes = [labels, sensitive_labels]
  }
}

resource "google_monitoring_uptime_check_config" "backend" {
  display_name = "backend-cloud-run"
  timeout      = "10s"
  period       = "300s"

  http_check {
    path         = "/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = "szczypka-web-backend"
      # Cloud Run's own `.uri` output includes the scheme - uptime_url wants
      # a bare host.
      host = replace(google_cloud_run_v2_service.backend.uri, "https://", "")
    }
  }
}

# Standard "did the uptime check fail" alerting policy - the filter/threshold
# shape here is Google's own documented pattern for wiring an uptime check to
# an alert policy, not something specific to this project.
resource "google_monitoring_alert_policy" "backend_uptime" {
  display_name = "Backend uptime check failing"
  combiner      = "OR"

  conditions {
    display_name = "Uptime health check failure"
    condition_threshold {
      filter          = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.\"check_id\" = \"${google_monitoring_uptime_check_config.backend.uptime_check_id}\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1

      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.*"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.slack_alerts.id]
}
