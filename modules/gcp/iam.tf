# Workload Identity Federation - keyless GitHub Actions auth (attribute
# condition on the `repository` claim from the OIDC token), distinct from the
# AWS OIDC + IAM role trust policy setup (see ../aws + github-actions-trust-policy.json
# at the repo root) - both kept in version control on purpose, as evidence of
# setting up two different federation models rather than copy-pasting one.
#
# CAVEAT: this block reconstructs the pool/provider from what's referenced in
# backend/.github/workflows/deploy-gcp.yml
# (projects/416578348143/locations/global/workloadIdentityPools/github-pool/providers/github-provider)
# and standard Google-documented GitHub Actions WIF setup - the exact
# attribute_mapping/attribute_condition below should be diffed against the
# live resource before `terraform import`:
#   gcloud iam workload-identity-pools providers describe github-provider \
#     --workload-identity-pool=github-pool --location=global --format=yaml
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
  description                = "Keyless auth for GitHub Actions workflows deploying to this project."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Restricts impersonation to Actions runs from this org - verify this
  # matches the live provider exactly (see CAVEAT above); Google's default
  # docs example uses this exact condition shape.
  attribute_condition = "assertion.repository_owner == 'SzczypkaWeb'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_actions_backend_deploy" {
  account_id   = "github-actions-backend-deploy"
  display_name = "GitHub Actions - backend deploy"
}

# Lets Actions runs FROM THIS SPECIFIC REPO (not just anyone with a GitHub
# Actions OIDC token) impersonate the service account above.
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.github_actions_backend_deploy.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/SzczypkaWeb/backend"
}

resource "google_project_iam_member" "deploy_run_admin" {
  project = "szczypka-web-backend"
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.github_actions_backend_deploy.email}"
}

resource "google_project_iam_member" "deploy_artifact_registry_writer" {
  project = "szczypka-web-backend"
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions_backend_deploy.email}"
}

# Cloud Run deploy needs to act as the runtime service account (default
# compute SA unless one was set explicitly) to attach it to new revisions.
resource "google_project_iam_member" "deploy_service_account_user" {
  project = "szczypka-web-backend"
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_actions_backend_deploy.email}"
}

# Required by the "Fetch DATABASE_URL for migrations" step in deploy-gcp.yml
# (a plain `gcloud secrets versions access`, separate from `--set-secrets` on
# the Cloud Run deploy itself, which only references secrets by name and
# doesn't need this role). RUNBOOK.md flagged this as possibly not granted
# yet - if `terraform plan`/`apply` here already show it as in place, that
# confirms it was granted manually at some point; if not, this is what closes
# that known gap.
resource "google_secret_manager_secret_iam_member" "deploy_secret_accessor" {
  for_each  = google_secret_manager_secret.backend
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.github_actions_backend_deploy.email}"
}
