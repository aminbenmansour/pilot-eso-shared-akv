output "client_id" {
  value = azurerm_user_assigned_identity.app.client_id
}

output "tenant_id" {
  value = azurerm_user_assigned_identity.app.tenant_id
}
