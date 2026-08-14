#!/usr/bin/env bash
# One-time: brings the already-existing (manually created via Portal, source
# = "Other") Azure resources under Terraform management, WITHOUT
# destroying/recreating anything. Run from inside modules/azure/, after
# `terraform init`. Requires the Azure CLI logged in (`az login`) - the
# subscription ID is read from it directly rather than hardcoded here, since
# it wasn't given to Claude and there's no reason to paste it into a file
# that isn't secret but also doesn't need to be.
#
# Genuinely safe to re-run - each import is guarded by `terraform state show`
# first, so an already-imported resource is skipped instead of hitting
# "Resource already managed by Terraform" (which, with `set -e`, kills the
# whole script partway through on a second run - see modules/gcp/import.sh
# for the same fix, found the hard way there first).
#
# After this finishes, run `terraform plan` - it should show (close to) zero
# changes. Any diff (e.g. sku_tier, differing location casing) is real drift
# to reconcile before ever running `terraform apply`.
set -euo pipefail

SUB_ID="$(az account show --query id -o tsv)"
RG="frontend-shell"
# react-app's actual resource group - NOT the same as $RG above (found via
# `az staticwebapp list` with no --resource-group filter; the two Static Web
# Apps turned out not to share a group despite what static_web_apps.tf used
# to claim). Only imported as a data source, not a managed resource - see
# the comment on data.azurerm_resource_group.marketplace in that file.
REACT_APP_RG="szczypka-marketplace-rg"

import_if_needed() {
  local addr="$1"
  local id="$2"
  if terraform state show "$addr" >/dev/null 2>&1; then
    echo "skip (already in state): $addr"
  else
    terraform import "$addr" "$id"
  fi
}

import_if_needed azurerm_resource_group.frontend \
  "/subscriptions/${SUB_ID}/resourceGroups/${RG}"

import_if_needed azurerm_static_web_app.react_app \
  "/subscriptions/${SUB_ID}/resourceGroups/${REACT_APP_RG}/providers/Microsoft.Web/staticSites/szczypka-react-app"

import_if_needed azurerm_static_web_app.frontend_shell \
  "/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Web/staticSites/app-shell"

# terraform-ci.yml's own Azure identity (oidc.tf) - App Registration,
# federated credential, service principal, custom role, role assignments.
# All created manually via `az` originally (see RUNBOOK.md/BLOG_NOTES.md for
# how each piece was arrived at) - real object/credential IDs below, found
# via `az ad app list` / `az ad app federated-credential list` /
# `az ad sp show` / `az role definition list` / `az role assignment list`.
INFRA_PLAN_APP_OBJECT_ID="0af1febb-fb4c-4f59-a782-ab4a2bde249b"
INFRA_PLAN_SP_OBJECT_ID="d3e95f96-cf10-4b6c-93eb-5ee672f5a1ba"
INFRA_PLAN_FEDCRED_ID="6cdddba4-80a7-41b7-836f-ef67a9c009d2"
STATIC_WEB_APP_PLAN_READER_ROLE_ID="2a6521cb-bf1b-4757-aa55-6d4330beb2f8"

import_if_needed azuread_application.infra_plan \
  "/applications/${INFRA_PLAN_APP_OBJECT_ID}"

import_if_needed azuread_service_principal.infra_plan \
  "/servicePrincipals/${INFRA_PLAN_SP_OBJECT_ID}"

import_if_needed azuread_application_federated_identity_credential.infra_plan_pr \
  "${INFRA_PLAN_APP_OBJECT_ID}/federatedIdentityCredential/${INFRA_PLAN_FEDCRED_ID}"

# Trickiest import ID format in this file - azurerm_role_definition expects
# "{role_definition_resource_id}|{scope}", not just the resource ID alone.
# If this errors, `terraform import` itself prints the exact expected format
# in the error message - trust that over this comment.
import_if_needed azurerm_role_definition.static_web_app_plan_reader \
  "/subscriptions/${SUB_ID}/providers/Microsoft.Authorization/roleDefinitions/${STATIC_WEB_APP_PLAN_READER_ROLE_ID}|/subscriptions/${SUB_ID}"

import_if_needed azurerm_role_assignment.infra_plan_reader_frontend_rg \
  "/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Authorization/roleAssignments/0cac200a-be27-48e5-b050-d3fa17445694"

import_if_needed azurerm_role_assignment.infra_plan_reader_marketplace_rg \
  "/subscriptions/${SUB_ID}/resourceGroups/${REACT_APP_RG}/providers/Microsoft.Authorization/roleAssignments/5a0e61e1-38cd-4e0e-96d2-08f9fc5f62a4"

import_if_needed azurerm_role_assignment.infra_plan_storage_reader \
  "/subscriptions/${SUB_ID}/resourceGroups/tfstate/providers/Microsoft.Storage/storageAccounts/szczypkawebtfstate/providers/Microsoft.Authorization/roleAssignments/328da5c0-fd37-4a2b-ac5a-3208e88b2bc7"

import_if_needed azurerm_role_assignment.infra_plan_storage_blob_data_reader \
  "/subscriptions/${SUB_ID}/resourceGroups/tfstate/providers/Microsoft.Storage/storageAccounts/szczypkawebtfstate/providers/Microsoft.Authorization/roleAssignments/1e20d3e7-f625-4bed-90f9-f33adb0545d2"

import_if_needed azurerm_role_assignment.infra_plan_swa_reader_frontend_shell \
  "/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Web/staticSites/app-shell/providers/Microsoft.Authorization/roleAssignments/dc43216d-f580-49b0-befd-e32c05e6abdc"

import_if_needed azurerm_role_assignment.infra_plan_swa_reader_react_app \
  "/subscriptions/${SUB_ID}/resourceGroups/${REACT_APP_RG}/providers/Microsoft.Web/staticSites/szczypka-react-app/providers/Microsoft.Authorization/roleAssignments/8644185b-635a-4799-ac50-cbd3e86845fc"

echo "Done. Now run: terraform plan   (expect ~zero diff; reconcile anything else before apply)"
