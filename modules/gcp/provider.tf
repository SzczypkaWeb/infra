terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Mirrors the AWS module's S3 backend (see ../aws/provider.tf) - GCS is
  # GCP's equivalent. Bucket must be created manually once, out of band,
  # before the first `terraform init` here (chicken-and-egg: Terraform can't
  # create the bucket that stores its own state) - e.g.
  #   gcloud storage buckets create gs://szczypka-web-tfstate-gcp \
  #     --project=szczypka-web-backend --location=europe-central2 \
  #     --uniform-bucket-level-access
  #   gcloud storage buckets update gs://szczypka-web-tfstate-gcp --versioning
  backend "gcs" {
    bucket = "szczypka-web-tfstate-gcp"
    prefix = "gcp/terraform.tfstate"
  }
}

provider "google" {
  project = "szczypka-web-backend"
  region  = "europe-central2"
}
