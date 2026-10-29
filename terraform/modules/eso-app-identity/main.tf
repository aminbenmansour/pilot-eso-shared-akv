locals {
  # Must match the "subject" of the federated identity credential below.
  service_account_name = coalesce(var.service_account_name, "eso-${var.app}")
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-eso-${var.app}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_federated_identity_credential" "app" {
  name                      = "eso-${var.app}"
  user_assigned_identity_id = azurerm_user_assigned_identity.app.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.namespace}:${local.service_account_name}"
}

# The External Secrets Operator reads the client and tenant IDs from these
# annotations to exchange the projected service account token for an Entra ID
# token. The namespace must already exist.
resource "kubernetes_service_account_v1" "app" {
  count = var.manage_service_account ? 1 : 0

  metadata {
    name      = local.service_account_name
    namespace = var.namespace

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.app.client_id
      "azure.workload.identity/tenant-id" = azurerm_user_assigned_identity.app.tenant_id
    }

    labels = var.service_account_labels
  }

  automount_service_account_token = false
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
