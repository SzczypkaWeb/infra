# Only the secret "containers" (metadata) are managed here, never the
# values/versions - those are sensitive and set out of band via
# `gcloud secrets versions add <name> --data-file=-` (see RUNBOOK.md), same
# principle as the AWS module only referencing aws_ssm_parameter.database_url
# by ARN in ecs.tf rather than storing its value in this repo/state.
locals {
  backend_secret_names = [
    "DATABASE_URL",
    "GOOGLE_CLIENT_ID",
    "GOOGLE_CLIENT_SECRET",
    "GOOGLE_CALLBACK_URL",
    "FRONTEND_ORIGIN",
    "JWT_ACCESS_SECRET",
    "JWT_REFRESH_SECRET",
    "SENTRY_DSN",
  ]
}

resource "google_secret_manager_secret" "backend" {
  for_each  = toset(local.backend_secret_names)
  secret_id = each.value

  replication {
    auto {}
  }
}

# Staging equivalents (DATABASE_URL_STAGING, etc., used by
# deploy-gcp-staging.yml) are deliberately NOT modeled here yet - per
# RUNBOOK.md section 9, none of them have been created in GCP Secret Manager
# yet (the whole staging DB/secret setup is still a manual TODO). Add a
# second `for_each` block here (secret_id = "${each.value}_STAGING") once
# that's actually done, so this module doesn't drift ahead of reality.
