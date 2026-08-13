# Both Static Web Apps (react-app, frontend-shell) share one resource group -
# this is what was actually created manually in the Azure Portal, name
# "frontend-shell" (a bit of a historical accident: created while setting up
# frontend-shell's app first, kept for both since there was no strong reason
# to split them).
resource "azurerm_resource_group" "frontend" {
  name     = "frontend-shell"
  location = "centralus"
}

# react-app - Module Federation remote, exposes ./Widget. Deployed by
# react-app/.github/workflows/azure-static-web-apps.yml (push to main).
resource "azurerm_static_web_app" "react_app" {
  name                = "szczypka-react-app"
  resource_group_name = azurerm_resource_group.frontend.name
  location            = azurerm_resource_group.frontend.location
  sku_tier            = "Free"
  sku_size            = "Free"

  # No "Enterprise-grade edge" (Azure Front Door) add-on - that's a paid
  # feature (~$17.52/app/month), deliberately skipped for a portfolio
  # project. Static assets are already served globally via the platform's
  # own default CDN either way.
}

# frontend-shell - Module Federation host / app-shell, consumes react-app's
# remoteEntry.js cross-origin (see staticwebapp.config.json in that repo for
# the CORS routes this requires) and exposes its own ./authStore. Deployed by
# frontend-shell/.github/workflows/azure-static-web-apps.yml (push to main).
resource "azurerm_static_web_app" "frontend_shell" {
  name                = "app-shell"
  resource_group_name = azurerm_resource_group.frontend.name
  location            = azurerm_resource_group.frontend.location
  sku_tier            = "Free"
  sku_size            = "Free"
}

# Both apps were provisioned with Deployment source = "Other" (not "GitHub")
# on purpose - see comments in each repo's azure-static-web-apps.yml. "GitHub"
# would have made Azure auto-generate and commit its own Oryx-based workflow
# file into the repo, which doesn't know about the private
# @szczypkaweb/shared-ui registry auth (npm.pkg.github.com) these builds need.
# "Other" just provisions the resource + a deployment token (see outputs.tf),
# and the already-hand-written workflow in each repo does the actual build.
