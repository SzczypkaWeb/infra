# Workload Identity Federation - keyless GitHub Actions auth (attribute
# condition on the `repository` claim from the OIDC token), distinct from the
# AWS OIDC + IAM role trust policy setup (see ../aws + github-actions-trust-policy.json
# at the repo root) - both kept in version control on purpose, as evidence of
# setting up two different federation models rather than copy-pasting one.
#
# Diffed against the live resource via `terraform plan` after import (see
# RUNBOOK.md) - the live attribute_condition was actually
# "assertion.repository=='SzczypkaWeb/backend'" (single-repo, not org-wide as
# originally assumed here). Widened deliberately to an explicit allowlist
# (not a full org-wide repository_owner condition) so the infra repo's own
# read-only CI (github-actions-infra-plan) can also use this pool, while
# keeping the pool-level gate as tight as it can be for the repos that
# actually need it - see the WIF trust-boundary discussion in BLOG_NOTES.md.
# Add more repos to this list only when they actually need WIF, not
# preemptively.
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

  # Explicit per-repo allowlist, not org-wide - this is the FIRST gate a
  # GitHub Actions OIDC token has to clear before GCP will even consider
  # exchanging it for a token, independent of the per-service-account
  # workloadIdentityUser bindings below (which are the second gate, already
  # scoped per-repo). Keeping this one tight too means a compromised
  # third-party Action running in some OTHER repo under this org couldn't
  # even attempt a token exchange here, regardless of any binding mistake.
  attribute_condition = "assertion.repository in ['SzczypkaWeb/backend', 'SzczypkaWeb/infra']"

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
  # Statically-known key set (a locals list), not the resource block itself -
  # using google_secret_manager_secret.backend directly as the for_each
  # source fails with "Invalid for_each argument" on a fresh
  # init+import, before any of those secret instances exist in state yet.
  # The VALUE below still references the resource (fine per Terraform's own
  # guidance - apply-time results only need to be in the map values, not the
  # keys), which keeps the implicit dependency on google_secret_manager_secret.backend.
  for_each  = toset(local.backend_secret_names)
  secret_id = google_secret_manager_secret.backend[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.github_actions_backend_deploy.email}"
}

# Read-only identity for the infra repo's own CI (`terraform plan` on PR -
# see terraform-ci.yml). Reuses the same WIF pool/provider above (its
# attribute_condition is already org-wide, not repo-specific) - only the
# per-repo impersonation binding and the granted role differ from the
# backend-deploy SA: no write access anywhere, `roles/viewer` is enough to
# read/diff Cloud Run, Artifact Registry, Secret Manager (container/metadata,
# not secret values), and the GCS state bucket in this same project.
resource "google_service_account" "github_actions_infra_plan" {
  account_id   = "github-actions-infra-plan"
  display_name = "GitHub Actions - infra terraform plan"
}

resource "google_service_account_iam_member" "infra_plan_wif_binding" {
  service_account_id = google_service_account.github_actions_infra_plan.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/SzczypkaWeb/infra"
}

resource "google_project_iam_member" "infra_plan_viewer" {
  project = "szczypka-web-backend"
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.github_actions_infra_plan.email}"
}
