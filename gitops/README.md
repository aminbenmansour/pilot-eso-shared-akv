# GitOps layout

Kubernetes configuration for the shared Key Vault pilot, consumed by Argo CD or
Flux CD. Tool-specific wiring is layered on top of this layout.

## Ownership

| Layer | Owner | Where |
|-------|-------|-------|
| Managed identity, federated credential, Key Vault RBAC | Terraform | `modules/eso-app-identity` |
| Workload identity service account | Terraform | `modules/eso-app-identity` |
| Namespace, External Secrets Operator | GitOps platform | `gitops/platform`, tool-specific platform manifests |
| `SecretStore` / `ExternalSecret` | GitOps application layer | `gitops/apps`, `gitops/environments` |
| Rendering and schema validation | CI | `.github/workflows/gitops.yml` |

The service account is intentionally **not** declared here. Its `client-id` and
`tenant-id` annotations come from the managed identity, so Terraform owns it.
Argo CD and Flux CD only reconcile resources that exist in Git, which means they
leave the Terraform-managed service account untouched. Do not add it to an
overlay.

## Layout

```
gitops/
  apps/glitchtip/base/          # env-agnostic manifests
    kustomization.yaml          # namespace: glitchtip
    secret-store.yaml
    external-secret.yaml
  environments/
    dev/kustomization.yaml      # base + dev vault URL, 5m refresh
    staging/kustomization.yaml  # base + staging vault URL, 15m refresh
    prod/kustomization.yaml     # base + prod vault URL, 1h refresh
  platform/
    namespace.yaml              # glitchtip namespace
```

## Environments

| Environment | Key Vault | Refresh |
|-------------|-----------|---------|
| dev | `https://kv-myproject-dev.vault.azure.net` | 5m |
| staging | `https://kv-myproject-staging.vault.azure.net` | 15m |
| prod | `https://kv-myproject-prod.vault.azure.net` | 1h |

Each environment uses its own Key Vault. The module's role assignment only
allows secrets prefixed with `<app>--`, so per-vault separation means a dev
identity cannot read staging or production secrets.

## Bootstrap order

1. Create the AKS cluster per environment and install the GitOps controller.
2. Apply the platform layer: the `glitchtip` namespace and External Secrets
   Operator.
3. Run Terraform for the application: managed identity, federated credential,
   Key Vault RBAC and the annotated service account.
4. Apply the environment overlay: `SecretStore` and `ExternalSecret`.

Step 2 must precede step 3 because the module creates the service account inside
the namespace. Until step 3 completes, the `SecretStore` reports an error and
ESO retries; nothing is lost, but the order above avoids the noise.

## Adding an application

1. Create `gitops/apps/<app>/base/` with a `kustomization.yaml` (set its
   `namespace`) and the `SecretStore`/`ExternalSecret` manifests. Secret keys
   must use the `<app>--` prefix.
2. Reference the base from every environment overlay and patch the vault URL and
   refresh interval where they differ.
3. Apply the Terraform module for the application.

## Promotion

- One directory per environment on `main`; no branch-per-environment, so what is
  deployed is always visible in a single revision history.
- Promotion is a pull request that changes the affected environment directory.
- Dev and staging may sync automatically; production should require an explicit
  approval or manual sync in the GitOps tool.

## Local validation

```bash
for env in dev staging prod; do
  kubectl kustomize "gitops/environments/${env}" \
    | kubeconform -strict -ignore-missing-schemas -summary \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
```
