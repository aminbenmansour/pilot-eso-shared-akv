# eso-app-identity

Terraform module that prepares an application to read its secrets from a shared
Azure Key Vault through the External Secrets Operator (ESO) and AKS workload
identity.

Per application it creates:

- a user-assigned managed identity,
- a federated identity credential bound to the AKS OIDC issuer and the ESO
  service account,
- a `Key Vault Secrets User` role assignment on the shared Key Vault, restricted
  to secrets prefixed with `<app>--`,
- the Kubernetes service account, annotated with the identity's `client-id` and
  `tenant-id`.

## Usage

```hcl
module "glitchtip_identity" {
  source = "git::https://github.com/aminbenmansour/pilot-eso-shared-akv.git//modules/eso-app-identity?ref=v1.0.0"

  app                 = "glitchtip"
  env                 = "dev"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  namespace           = "glitchtip"
  key_vault_id        = azurerm_key_vault.this.id

  oidc_issuer_url = data.azurerm_kubernetes_cluster.this.oidc_issuer_url
}
```

Pin `ref` to a tag (or a commit SHA). Branches move and are not reproducible.

The repository is public, so no credentials are needed. If you mirror or fork it
privately, use SSH:

```hcl
source = "git::ssh://git@github.com/aminbenmansour/pilot-eso-shared-akv.git//modules/eso-app-identity?ref=v1.0.0"
```

or keep the HTTPS form and provide credentials through a credential helper, a
`url.<base>.insteadOf` rewrite, or `GIT_ASKPASS` in CI. Avoid embedding tokens in
`source`, since module sources are recorded in state and in `.terraform/modules`.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 (OpenTofu >= 1.6) |
| [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest) | tested with ~> 5.10 |
| [kubernetes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest) | tested with ~> 3.4 |

The `kubernetes` provider cannot be configured by the module; the caller must
provide it. Either rely on the current kubeconfig context:

```hcl
provider "kubernetes" {}
```

or point it explicitly at the cluster (required for CI):

```hcl
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_key)
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| app | Application name used for identity, federation, and secret prefix matching. | `string` | n/a | yes |
| env | Environment name (e.g. dev, prod). | `string` | n/a | yes |
| location | Azure location where the user-assigned identity is created. | `string` | n/a | yes |
| resource_group_name | Resource group containing the managed identity and federated credential. | `string` | n/a | yes |
| oidc_issuer_url | AKS OIDC issuer URL (from the AKS cluster resource). | `string` | n/a | yes |
| namespace | Kubernetes namespace where the External Secrets Operator service account exists. | `string` | n/a | yes |
| key_vault_id | Resource ID of the Azure Key Vault. | `string` | n/a | yes |
| manage_service_account | Whether to create the Kubernetes service account with workload identity annotations. | `bool` | `true` | no |
| service_account_name | Service account name. Defaults to `eso-<app>`. | `string` | `null` | no |
| service_account_labels | Additional labels applied to the service account. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| client_id | Client ID of the user-assigned identity. |
| tenant_id | Tenant ID of the user-assigned identity. |
| service_account_name | Name of the service account (managed or expected). |
| namespace | Namespace of the service account. |

## Notes

- The Kubernetes namespace must exist before applying.
- The service account name feeds the federated credential subject, so changing
  it replaces the credential.
- ESO must be allowed to create service account tokens for this account; this is
  normally part of its cluster role.
- If the service account already exists outside Terraform, import it or set
  `manage_service_account = false` and apply the annotations yourself:

  ```bash
  tofu import 'module.glitchtip_identity.kubernetes_service_account_v1.app[0]' glitchtip/eso-glitchtip
  ```
