#!/usr/bin/env bash
# One-time: brings the already-existing (manually created) GCP resources
# under Terraform management, WITHOUT destroying/recreating anything.
# Run from inside modules/gcp/, after `terraform init`.
#
# Safe to re-run - `terraform import` on an already-imported resource just
# errors "Resource already managed", it doesn't touch real infra either way.
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

terraform import google_artifact_registry_repository.backend \
  "projects/${PROJECT}/locations/${REGION}/repositories/backend"

for secret in DATABASE_URL GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_CALLBACK_URL \
              FRONTEND_ORIGIN JWT_ACCESS_SECRET JWT_REFRESH_SECRET SENTRY_DSN; do
  terraform import "google_secret_manager_secret.backend[\"${secret}\"]" \
    "projects/${PROJECT}/secrets/${secret}"
  terraform import "google_secret_manager_secret_iam_member.deploy_secret_accessor[\"${secret}\"]" \
    "projects/${PROJECT}/secrets/${secret} roles/secretmanager.secretAccessor serviceAccount:${SA_EMAIL}"
done

terraform import google_cloud_run_v2_service.backend \
  "projects/${PROJECT}/locations/${REGION}/services/backend"

terraform import google_cloud_run_v2_service_iam_member.backend_public \
  "projects/${PROJECT}/locations/${REGION}/services/backend roles/run.invoker allUsers"

terraform import google_iam_workload_identity_pool.github \
  "projects/${PROJECT}/locations/global/workloadIdentityPools/github-pool"

terraform import google_iam_workload_identity_pool_provider.github \
  "projects/${PROJECT}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

terraform import google_service_account.github_actions_backend_deploy \
  "projects/${PROJECT}/serviceAccounts/${SA_EMAIL}"

terraform import google_service_account_iam_member.wif_binding \
  "projects/${PROJECT}/serviceAccounts/${SA_EMAIL} roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/projects/${PROJECT}/locations/global/workloadIdentityPools/github-pool/attribute.repository/SzczypkaWeb/backend"

terraform import google_project_iam_member.deploy_run_admin \
  "${PROJECT} roles/run.admin serviceAccount:${SA_EMAIL}"

terraform import google_project_iam_member.deploy_artifact_registry_writer \
  "${PROJECT} roles/artifactregistry.writer serviceAccount:${SA_EMAIL}"

terraform import google_project_iam_member.deploy_service_account_user \
  "${PROJECT} roles/iam.serviceAccountUser serviceAccount:${SA_EMAIL}"

echo "Done. Now run: terraform plan   (expect ~zero diff; reconcile anything else before apply)"
