# CORRECTION (found via `az staticwebapp list` while setting up Terraform CI -
# see RUNBOOK.md): the two Static Web Apps do NOT share one resource group,
# despite what this comment used to claim. frontend-shell's app ("app-shell")
# is in "frontend-shell"; react-app's ("szczypka-react-app") is in a
# DIFFERENT, separately-created group, "szczypka-marketplace-rg". Modeled as
# a data source (read-only reference), not a managed resource - unlike
# "frontend-shell" below, this group's full lifecycle/contents weren't
# necessarily meant to be Terraform-owned, and importing it as a resource
# would make `terraform destroy`/state operations here able to affect
# whatever else might end up in it.
data "azurerm_resource_group" "marketplace" {
  name = "szczypka-marketplace-rg"
}

resource "azurerm_resource_group" "frontend" {
  name = "frontend-shell"
  # Real value, confirmed via `terraform plan` after import - was wrongly
  # hardcoded as "centralus" here before, which would have made Terraform
  # try to DESTROY AND RECREATE this live resource group (a `location`
  # change forces replacement) the moment anyone ran `apply`. Caught before
  # that happened - see RUNBOOK.md.
  location = "polandcentral"
}

# react-app - Module Federation remote, exposes ./Widget. Deployed by
# react-app/.github/workflows/azure-static-web-apps.yml (push to main).
resource "azurerm_static_web_app" "react_app" {
  name                = "szczypka-react-app"
  resource_group_name = data.azurerm_resource_group.marketplace.name
  # Deliberately NOT data.azurerm_resource_group.marketplace.location - a
  # resource group's own `location` (where its metadata lives) is
  # independent of the region its child resources actually run in, and
  # Static Web Apps only support a small fixed set of regions (polandcentral
  # isn't one of them). This resource's real region, confirmed the same way
  # as the resource group's above, is centralus - coupling it to the parent
  # RG's location was a bad assumption that would also have forced a
  # destroy-and-recreate (new resource = new random hostname, breaking
  # frontend-shell's Module Federation remote URL and the CORS/OAuth config
  # pointing at the old one).
  location = "centralus"
  sku_tier            = "Free"
  sku_size            = "Free"

  # repository_url/repository_branch are read-only-in-practice here: the
  # azurerm provider requires them together with repository_token (a real
  # GitHub PAT) as a group, and we deliberately don't want Azure holding a
  # PAT / auto-managing this repo (see "Other" deployment source note at the
  # bottom of this file). Leaving them unset means `terraform plan` shows a
  # harmless in-place diff nulling out this metadata - not a forced
  # replacement, no functional effect on how deploys actually happen.

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
  # Same reasoning as react_app above - hardcoded to the real region
  # (centralus), not derived from the resource group's own (different)
  # location.
  location            = "centralus"
  sku_tier            = "Free"
  sku_size            = "Free"

  # Same reasoning as react_app above re: repository_url/repository_branch
  # left unset on purpose.
}

# Both apps were provisioned with Deployment source = "Other" (not "GitHub")
# on purpose - see comments in each repo's azure-static-web-apps.yml. "GitHub"
# would have made Azure auto-generate and commit its own Oryx-based workflow
# file into the repo, which doesn't know about the private
# @szczypkaweb/shared-ui registry auth (npm.pkg.github.com) these builds need.
# "Other" just provisions the resource + a deployment token (see outputs.tf),
# and the already-hand-written workflow in each repo does the actual build.
