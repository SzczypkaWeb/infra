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

echo "Done. Now run: terraform plan   (expect ~zero diff; reconcile anything else before apply)"
