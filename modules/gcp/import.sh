#!/usr/bin/env bash
# One-time: brings the already-existing (manually created) GCP resources
# under Terraform management, WITHOUT destroying/recreating anything.
# Run from inside modules/gcp/, after `terraform init`.
#
# Genuinely safe to re-run - each import is guarded by `terraform state show`
# first, so an already-imported resource is skipped instead of hitting
# "Resource already managed by Terraform" (which, with `set -e`, would kill
# the whole script partway through on a second run - that's what plain
# `terraform import` on every line used to do here).
#
# After this finishes, run `terraform plan` - it should show (close to) zero
# changes. Any diff it does show is real drift between what's actually
# deployed and what these .tf files describe (e.g. an IAM binding granted
# manually that isn't modeled here yet) - reconcile that before ever running
# `terraform apply`, don't just apply blindly.
set -euo pipefail

PROJECT="szczypka-web-backend"
REGION="europe-central2"
SA_EMAIL="github-actions-backend-deploy@${PROJECT}.iam.gserviceaccount.com"

# IAM bindings for a WIF principalSet member are always stored by Google
# using the PROJECT NUMBER, never the project ID, regardless of which form
# you used when granting the binding - confirmed against Google's own docs.
# Using the project ID here (like everywhere else in this script) makes
# `terraform import` fail with "Cannot find binding for..." even though the
# binding genuinely exists - it's just indexed under a different string.
PROJECT_NUMBER="416578348143"

import_if_needed() {
  local addr="$1"
  local id="$2"
  if terraform state show "$addr" >/dev/null 2>&1; then
    echo "skip (already in state): $addr"
  else
    terraform import "$addr" "$id"
  fi
}

import_if_needed google_artifact_registry_repository.backend \
  "projects/${PROJECT}/locations/${REGION}/repositories/backend"

for secret in DATABASE_URL GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_CALLBACK_URL \
              FRONTEND_ORIGIN JWT_ACCESS_SECRET JWT_REFRESH_SECRET SENTRY_DSN; do
  import_if_needed "google_secret_manager_secret.backend[\"${secret}\"]" \
    "projects/${PROJECT}/secrets/${secret}"
  import_if_needed "google_secret_manager_secret_iam_member.deploy_secret_accessor[\"${secret}\"]" \
    "projects/${PROJECT}/secrets/${secret} roles/secretmanager.secretAccessor serviceAccount:${SA_EMAIL}"
done

import_if_needed google_cloud_run_v2_service.backend \
  "projects/${PROJECT}/locations/${REGION}/services/backend"

import_if_needed google_cloud_run_v2_service_iam_member.backend_public \
  "projects/${PROJECT}/locations/${REGION}/services/backend roles/run.invoker allUsers"

import_if_needed google_iam_workload_identity_pool.github \
  "projects/${PROJECT}/locations/global/workloadIdentityPools/github-pool"

import_if_needed google_iam_workload_identity_pool_provider.github \
  "projects/${PROJECT}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

import_if_needed google_service_account.github_actions_backend_deploy \
  "projects/${PROJECT}/serviceAccounts/${SA_EMAIL}"

import_if_needed google_service_account_iam_member.wif_binding \
  "projects/${PROJECT}/serviceAccounts/${SA_EMAIL} roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/SzczypkaWeb/backend"

import_if_needed google_project_iam_member.deploy_run_admin \
  "${PROJECT} roles/run.admin serviceAccount:${SA_EMAIL}"

import_if_needed google_project_iam_member.deploy_artifact_registry_writer \
  "${PROJECT} roles/artifactregistry.writer serviceAccount:${SA_EMAIL}"

import_if_needed google_project_iam_member.deploy_service_account_user \
  "${PROJECT} roles/iam.serviceAccountUser serviceAccount:${SA_EMAIL}"

# Read-only SA for the infra repo's own Terraform CI (terraform-ci.yml) -
# created manually via gcloud (see RUNBOOK.md), same chicken-and-egg reason
# as everything else in this script: Terraform can't create the identity
# that Terraform CI itself needs to run.
INFRA_PLAN_SA_EMAIL="github-actions-infra-plan@${PROJECT}.iam.gserviceaccount.com"

import_if_needed google_service_account.github_actions_infra_plan \
  "projects/${PROJECT}/serviceAccounts/${INFRA_PLAN_SA_EMAIL}"

import_if_needed google_service_account_iam_member.infra_plan_wif_binding \
  "projects/${PROJECT}/serviceAccounts/${INFRA_PLAN_SA_EMAIL} roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/SzczypkaWeb/infra"

import_if_needed google_project_iam_member.infra_plan_viewer \
  "${PROJECT} roles/viewer serviceAccount:${INFRA_PLAN_SA_EMAIL}"

# Slack notification channel (monitoring.tf) - must be created via the Cloud
# Console's own Slack OAuth flow first (see RUNBOOK.md), NOT by
# `terraform apply` from scratch - a Terraform-created Slack channel silently
# never delivers real messages (see the comment in monitoring.tf). Fill in
# the real ID below once it exists - find it with:
#   gcloud alpha monitoring channels list --project="${PROJECT}"
SLACK_CHANNEL_ID="16084917688367049121"

if [ -z "$SLACK_CHANNEL_ID" ]; then
  echo "skip: google_monitoring_notification_channel.slack_alerts (set SLACK_CHANNEL_ID in import.sh first - see RUNBOOK.md)"
else
  import_if_needed google_monitoring_notification_channel.slack_alerts \
    "projects/${PROJECT}/notificationChannels/${SLACK_CHANNEL_ID}"
fi

echo "Done. Now run: terraform plan   (expect ~zero diff; reconcile anything else before apply)"
