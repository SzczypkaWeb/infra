#!/usr/bin/env bash
# One-time: brings the already-existing (manually created via Portal, source
# = "Other") Azure resources under Terraform management, WITHOUT
# destroying/recreating anything. Run from inside modules/azure/, after
# `terraform init`. Requires the Azure CLI logged in (`az login`) - the
# subscription ID is read from it directly rather than hardcoded here, since
# it wasn't given to Claude and there's no reason to paste it into a file
# that isn't secret but also doesn't need to be.
#
# After this finishes, run `terraform plan` - it should show (close to) zero
# changes. Any diff (e.g. sku_tier, differing location casing) is real drift
# to reconcile before ever running `terraform apply`.
set -euo pipefail

SUB_ID="$(az account show --query id -o tsv)"
RG="frontend-shell"

terraform import azurerm_resource_group.frontend \
  "/subscriptions/${SUB_ID}/resourceGroups/${RG}"

terraform import azurerm_static_web_app.react_app \
  "/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Web/staticSites/szczypka-react-app"

terraform import azurerm_static_web_app.frontend_shell \
  "/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Web/staticSites/app-shell"

echo "Done. Now run: terraform plan   (expect ~zero diff; reconcile anything else before apply)"
