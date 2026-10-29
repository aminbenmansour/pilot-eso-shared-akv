output "client_id" {
  value = azurerm_user_assigned_identity.app.client_id
}

output "tenant_id" {
  value = azurerm_user_assigned_identity.app.tenant_id
}

output "service_account_name" {
  value = local.service_account_name
}

output "namespace" {
  value = var.namespace
}
