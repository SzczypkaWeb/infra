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

  # Without this, some APIs (billingbudgets.googleapis.com being the one
  # that surfaced it) get quota-checked against whatever project ADC
  # defaults to locally - not the `project` above - which for local `gcloud`
  # sessions on this machine turned out to be the old default "My First
  # Project" (came up before, when GCP Console kept defaulting there too).
  # `gcloud auth application-default set-quota-project` does NOT fix this -
  # the Terraform provider has its own separate resolution path, ignoring
  # ADC's own quota_project_id field. This is the documented, correct fix:
  # explicitly pin the billing/quota project and force every API call to
  # use it.
  billing_project       = "szczypka-web-backend"
  user_project_override = true
}
