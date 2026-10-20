module "glitchtip_identity" {
  source = "../../modules/eso-app-identity"

  app                 = "glitchtip"
  env                 = "dev"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  namespace           = "glitchtip"

  oidc_issuer_url = data.terraform_remote_state.aks.outputs.oidc_issuer_url
  key_vault_id    = data.terraform_remote_state.secrets.outputs.key_vault_id
}
