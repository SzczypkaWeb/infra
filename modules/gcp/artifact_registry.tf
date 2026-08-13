# Backs the image referenced by .github/workflows/deploy-gcp.yml /
# deploy-gcp-staging.yml (europe-central2-docker.pkg.dev/szczypka-web-backend/backend/api).
resource "google_artifact_registry_repository" "backend" {
  repository_id = "backend"
  location      = "europe-central2"
  format        = "DOCKER"
  description   = "Docker images for the NestJS backend, built and pushed by deploy-gcp.yml / deploy-gcp-staging.yml"
}
