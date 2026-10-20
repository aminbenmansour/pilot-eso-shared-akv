locals {
  oidc_issuer_url = coalesce(
    var.oidc_issuer_url,
    data.terraform_remote_state.aks.outputs.oidc_issuer_url
  )
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-eso-${var.app}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_federated_identity_credential" "app" {
  name                = "eso-${var.app}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:eso-${var.app}"
}

resource "azurerm_role_assignment" "secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id

  # Enforce application-level secret isolation within a shared Key Vault.
  # This identity may only read secrets prefixed with "${var.app}--".
  condition_version = "2.0"
  condition         = <<-EOT
    (
      !(ActionMatches{'Microsoft.KeyVault/vaults/secrets/getSecret/action'})
      OR
      @Resource[Microsoft.KeyVault/vaults/secrets:name] StringStartsWith '${var.app}--'
    )
  EOT
}
