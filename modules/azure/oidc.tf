# The Azure identity terraform-ci.yml itself uses to authenticate (OIDC,
# read-only) - App Registration, federated credential, a custom RBAC role,
# and the role assignments granting it read access to exactly what it needs
# to plan. This mirrors what modules/gcp/iam.tf already models for GCP's
# equivalent identity (github_actions_infra_plan) - until now this side was
# `az`-CLI-only, a real asymmetry flagged in RUNBOOK.md. Bootstrapped
# manually (same chicken-and-egg reason as everywhere else: this identity is
# what lets Terraform CI run at all, so Terraform CI can't be the thing that
# first creates it), then imported here - see import.sh.
#
# Subscription used for scoping - hardcoded to match how every other literal
# ID in this module is handled (no variables.tf in this repo; see
# provider.tf/static_web_apps.tf for the same style).
locals {
  subscription_id = "021d33ca-8cbe-42ea-873f-53ab01e1b61c"
  # The tfstate storage account isn't itself a managed resource in this
  # module (same chicken-and-egg bootstrap category as the GCS bucket in
  # ../gcp - see provider.tf) - hardcoded here for the two role assignments
  # that target it.
  tfstate_storage_account_id = "/subscriptions/021d33ca-8cbe-42ea-873f-53ab01e1b61c/resourceGroups/tfstate/providers/Microsoft.Storage/storageAccounts/szczypkawebtfstate"
}

resource "azuread_application" "infra_plan" {
  display_name = "github-actions-infra-plan"

  # Ownership can drift from whoever's `az login` identity happened to
  # create it (or accumulate co-owners over time) without that being a real
  # config change worth Terraform fighting over.
  lifecycle {
    ignore_changes = [owners]
  }
}

resource "azuread_service_principal" "infra_plan" {
  client_id = azuread_application.infra_plan.client_id
}

# Subject uses GitHub's "immutable subject claims" format (numeric org/repo
# IDs embedded alongside the names) - see BLOG_NOTES.md for the saga of
# finding this out the hard way when the old name-only format started
# getting rejected with AADSTS700213. Copied verbatim from the real
# federated credential rather than reconstructed from the documented
# pattern, to avoid re-learning that lesson.
resource "azuread_application_federated_identity_credential" "infra_plan_pr" {
  application_id = azuread_application.infra_plan.id
  display_name   = "github-infra-pr"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:SzczypkaWeb@309075262/infra@1311931455:pull_request"
  audiences      = ["api://AzureADTokenExchange"]
}

# No built-in Azure role grants read-only access to a Static Web App's
# secrets/app settings without much broader write access too - see
# BLOG_NOTES.md for how this was discovered action-by-action, two separate
# 403s in turn (listSecrets, then listAppSettings).
resource "azurerm_role_definition" "static_web_app_plan_reader" {
  name        = "Static Web App Plan Reader"
  scope       = "/subscriptions/${local.subscription_id}"
  description = "Read-only access to Static Web Apps including listSecrets/listAppSettings, for Terraform plan-only CI - no write actions."

  permissions {
    actions = [
      "Microsoft.Web/staticSites/read",
      "Microsoft.Web/staticSites/listSecrets/action",
      "Microsoft.Web/staticSites/listAppSettings/action",
    ]
  }

  assignable_scopes = ["/subscriptions/${local.subscription_id}"]
}

# Plain `Reader` at each resource group - control-plane read access (see
# BLOG_NOTES.md: this is separate from, and doesn't substitute for, the
# data-plane `Storage Blob Data Reader` role below - one of several
# RBAC-layering surprises hit while wiring this up originally).
resource "azurerm_role_assignment" "infra_plan_reader_frontend_rg" {
  scope                = azurerm_resource_group.frontend.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_plan.object_id
}

resource "azurerm_role_assignment" "infra_plan_reader_marketplace_rg" {
  scope                = data.azurerm_resource_group.marketplace.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_plan.object_id
}

# Storage account (tfstate) - both Reader (control-plane) and Storage Blob
# Data Reader (data-plane, needed because provider.tf's backend uses
# use_azuread_auth = true rather than shared-key listKeys).
resource "azurerm_role_assignment" "infra_plan_storage_reader" {
  scope                = local.tfstate_storage_account_id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.infra_plan.object_id
}

resource "azurerm_role_assignment" "infra_plan_storage_blob_data_reader" {
  scope                = local.tfstate_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.infra_plan.object_id
}

# The custom role, scoped to each Static Web App individually (not the
# whole resource group) - no reason to let this identity read secrets on
# anything beyond exactly the two resources it needs to plan.
resource "azurerm_role_assignment" "infra_plan_swa_reader_frontend_shell" {
  scope              = azurerm_static_web_app.frontend_shell.id
  role_definition_id = azurerm_role_definition.static_web_app_plan_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_plan.object_id
}

resource "azurerm_role_assignment" "infra_plan_swa_reader_react_app" {
  scope              = azurerm_static_web_app.react_app.id
  role_definition_id = azurerm_role_definition.static_web_app_plan_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_plan.object_id
}

# azurerm_consumption_budget_subscription (budget.tf) is scoped at the
# subscription root, not any resource group - none of the RG/resource-scoped
# assignments above cover it, so terraform-ci's plan job got a 401 trying to
# read it (Microsoft.Consumption/budgets isn't included in the narrower
# scopes above). `Cost Management Reader` is the built-in role for exactly
# this - read access to cost/budget data, nothing else - deliberately not
# plain `Reader` at subscription scope, which would hand this read-only CI
# identity visibility into every resource in the subscription instead of
# just the one new resource type it actually needs.
resource "azurerm_role_assignment" "infra_plan_cost_management_reader" {
  scope                = "/subscriptions/${local.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = azuread_service_principal.infra_plan.object_id
}

# Self-referential gap surfaced by the assignment above: the moment ANY role
# assignment is scoped at the subscription root (rather than a resource/RG
# this identity already has a role on), terraform-ci's plan job can no longer
# read that assignment object back on a later run -
# `Microsoft.Authorization/roleAssignments/read` isn't included in `Cost
# Management Reader` (that role only covers Microsoft.CostManagement/
# Microsoft.Consumption actions), and this identity has no OTHER role at the
# subscription root to fall back on. Every other role_assignment resource in
# this file avoided this because it's scoped at the same RG/resource where
# this identity already holds Reader (or the custom SWA role), which grants
# roleAssignments/read at that scope for free - reading role DEFINITIONS
# (see static_web_app_plan_reader above) needs no permission at all in Azure,
# it's globally readable; role ASSIGNMENTS are not.
#
# Fix: a second custom role, narrowly scoped to exactly
# Microsoft.Authorization/roleAssignments/read - deliberately not built-in
# `Reader` at subscription scope, which would hand this read-only CI identity
# visibility into every resource in the subscription just to solve a read-back
# problem on two specific objects. Self-covering once applied: this
# assignment is itself scoped at the subscription root, so once it exists it
# grants the read access needed to read itself back on the next plan - same
# shape as the RG-scoped assignments above.
resource "azurerm_role_definition" "role_assignment_reader" {
  name        = "Role Assignment Reader"
  scope       = "/subscriptions/${local.subscription_id}"
  description = "Read-only access to Microsoft.Authorization/roleAssignments at subscription scope, for Terraform plan-only CI to read back subscription-scoped role assignments it manages."

  permissions {
    actions = [
      "Microsoft.Authorization/roleAssignments/read",
    ]
  }

  assignable_scopes = ["/subscriptions/${local.subscription_id}"]
}

resource "azurerm_role_assignment" "infra_plan_role_assignment_reader" {
  scope              = "/subscriptions/${local.subscription_id}"
  role_definition_id = azurerm_role_definition.role_assignment_reader.role_definition_resource_id
  principal_id       = azuread_service_principal.infra_plan.object_id
}
