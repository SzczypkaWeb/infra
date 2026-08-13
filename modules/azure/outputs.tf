# Deployment tokens - paste these into each repo's GitHub secret
# AZURE_STATIC_WEB_APPS_API_TOKEN (Settings -> Secrets and variables ->
# Actions). `sensitive = true` keeps them out of plain `terraform output` /
# plan diffs; use `terraform output -raw <name>` to actually read one.
output "react_app_deployment_token" {
  value     = azurerm_static_web_app.react_app.api_key
  sensitive = true
}

output "frontend_shell_deployment_token" {
  value     = azurerm_static_web_app.frontend_shell.api_key
  sensitive = true
}

output "react_app_default_hostname" {
  value = azurerm_static_web_app.react_app.default_host_name
}

output "frontend_shell_default_hostname" {
  value = azurerm_static_web_app.frontend_shell.default_host_name
}
