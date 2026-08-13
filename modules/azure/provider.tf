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
  backend "azurerm" {
    resource_group_name = "tfstate"
    storage_account_name = "szczypkawebtfstate"
    container_name        = "tfstate"
    key                    = "azure/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}
