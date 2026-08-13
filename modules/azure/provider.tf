terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Mirrors the AWS module's S3 backend / GCP module's GCS backend (see
  # ../aws/provider.tf, ../gcp/provider.tf) - an Azure Storage Account
  # container is the equivalent here. Same chicken-and-egg note applies:
  # create this storage account manually, out of band, before the first
  # `terraform init` in this module.
  #   az group create --name tfstate --location centralus
  #   az storage account create --name szczypkawebtfstate --resource-group tfstate --sku Standard_LRS
  #   az storage container create --name tfstate --account-name szczypkawebtfstate
  # use_azuread_auth: without this, the backend authenticates to the blob
  # DATA plane by calling listKeys on the storage account and using the
  # resulting shared key - which needs a much more privileged role
  # (something that can read account keys) than we want to grant a
  # read-only CI identity. With it, the backend uses the caller's own AAD/
  # OIDC token directly against the blob, so `Storage Blob Data Reader`
  # (already granted - see RUNBOOK.md) is enough on its own. Found via a
  # real `terraform-ci.yml` run failing with "AuthorizationFailed ...
  # listKeys/action" - local usage (`az login`) keeps working the same way,
  # since an Azure AD token is what `az login` already provides too.
  backend "azurerm" {
    resource_group_name = "tfstate"
    storage_account_name = "szczypkawebtfstate"
    container_name        = "tfstate"
    key                    = "azure/terraform.tfstate"
    use_azuread_auth       = true
  }
}

provider "azurerm" {
  features {}
}
