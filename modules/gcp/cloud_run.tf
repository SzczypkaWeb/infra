# Mirrors what `gcloud run deploy backend --set-secrets=... --set-env-vars=...`
# in .github/workflows/deploy-gcp.yml actually configures on the live
# service - see `gcloud run revisions describe <latest> --format="yaml(spec.containers[0].env)"`,
# which is exactly what this block was written from.
resource "google_cloud_run_v2_service" "backend" {
  name     = "backend"
  location = "europe-central2"
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      # Placeholder tag - CI always deploys a specific immutable :sha tag
      # (never :latest), see the `lifecycle.ignore_changes` below. This value
      # only matters for the very first `terraform apply` that creates the
      # service; every real deploy since then has come from deploy-gcp.yml.
      image = "europe-central2-docker.pkg.dev/szczypka-web-backend/backend/api:latest"

      ports {
        container_port = 3000
      }

      dynamic "env" {
        for_each = toset(local.backend_secret_names)
        content {
          name = env.value
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.backend[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      env {
        name  = "JWT_ACCESS_EXPIRES"
        value = "900"
      }
      env {
        name  = "JWT_REFRESH_EXPIRES"
        value = "604800"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # CI (deploy-gcp.yml) deploys a new revision on every push to main with
      # a fresh :sha-tagged image, completely independent of Terraform.
      # Without this, every `terraform plan` after a real deploy would show a
      # "drift" trying to revert the image back to the placeholder above.
      template[0].containers[0].image,
    ]
  }
}

# `--allow-unauthenticated` in the deploy command = granting allUsers the
# invoker role. The API itself still enforces its own JWT auth (see
# backend/src/auth) - this only controls whether Cloud Run's own layer
# requires a Google-signed ID token in front of that.
resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  name     = google_cloud_run_v2_service.backend.name
  location = google_cloud_run_v2_service.backend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# backend-staging (deploy-gcp-staging.yml) is deliberately NOT modeled yet -
# its secrets (secrets.tf) haven't been created in GCP either, and defining
# the service without them would either fail to plan or silently point at
# secrets that don't exist. Add once RUNBOOK.md section 9's staging TODOs are
# actually done - should be close to a copy of the block above with
# `_STAGING`-suffixed secret refs and name = "backend-staging".
