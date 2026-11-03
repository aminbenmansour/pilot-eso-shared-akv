# GitOps examples

Three independent, self-contained ways to deploy the same application to the
same three environments. Pick the one that matches your platform; each directory
can be read, copied or deleted on its own.

| Example | Controller | Entry point |
|---------|------------|-------------|
| [`plain/`](plain/README.md) | none, `kubectl` + Kustomize | `./gitops/plain/deploy.sh dev` |
| [`argocd/`](argocd/README.md) | Argo CD, hub cluster | `./gitops/argocd/deploy.sh` |
| [`flux/`](flux/README.md) | Flux CD, agent per cluster | `./gitops/flux/deploy.sh dev` |

All three deploy the same resources: a `SecretStore` and an `ExternalSecret` that
pull the Glitchtip secrets from the environment's Azure Key Vault into a
Kubernetes `Secret`.

## Layout

```
gitops/
  plain/                      # no controller
    manifests/{platform,apps,environments}
    deploy.sh
  argocd/                     # hub-and-spoke
    bootstrap/                # AppProjects + ApplicationSets
    manifests/{platform,apps,environments}
    deploy.sh
  flux/                       # one agent per cluster
    clusters/<env>/           # Flux Kustomizations
    manifests/{platform,apps,environments}
    deploy.sh
```

Each example owns its copy of `manifests/`: the namespace, the app base and the
three environment overlays. The copies are identical by design — a small amount
of duplication in exchange for examples that can stand alone. CI fails if they
drift.

## Environments

| Environment | Key Vault | Refresh |
|-------------|-----------|---------|
| dev | `https://kv-myproject-dev.vault.azure.net` | 5m |
| staging | `https://kv-myproject-staging.vault.azure.net` | 15m |
| prod | `https://kv-myproject-prod.vault.azure.net` | 1h |

One cluster and one Key Vault per environment. The Terraform module only grants
access to secrets prefixed with `<app>--`, so per-vault separation means a dev
identity cannot read staging or production secrets.

## Ownership

| Layer | Owner | Where |
|-------|-------|-------|
| Managed identity, federated credential, Key Vault RBAC | Terraform | `modules/eso-app-identity` |
| Workload identity service account | Terraform | `modules/eso-app-identity` |
| Namespace, External Secrets Operator | GitOps platform | `<example>/manifests/platform`, `<example>/bootstrap` or `<example>/clusters` |
| `SecretStore` / `ExternalSecret` | GitOps application layer | `<example>/manifests/apps`, `<example>/manifests/environments` |
| Rendering and schema validation | CI | `.github/workflows/gitops.yml` |

The service account is intentionally **not** declared in any example. Its
`client-id` and `tenant-id` annotations come from the managed identity, so
Terraform owns it. Argo CD and Flux CD only reconcile resources that exist in
Git, which means they leave the Terraform-managed service account untouched. Do
not add it to an overlay.

## Bootstrap order

1. Create the AKS cluster per environment and install the GitOps controller
   (skip this step for the plain example).
2. Apply the platform layer: the `glitchtip` namespace and External Secrets
   Operator.
3. Run Terraform for the application: managed identity, federated credential,
   Key Vault RBAC and the annotated service account.
4. Apply the environment overlay.

Step 2 must precede step 3 because the module creates the service account inside
the namespace. Until step 3 completes, the `SecretStore` reports an error and
ESO retries; nothing is lost, but the order above avoids the noise.

## Promotion

- One directory per environment on `main`; no branch-per-environment, so what is
  deployed is always visible in a single revision history.
- Promotion is a pull request that changes the affected environment directory.
- Dev and staging may sync automatically; production should require an explicit
  approval or manual sync in the GitOps tool.

## Local validation

The workflow discovers every `kustomization.yaml` under `gitops`, so the same
checks run locally:

```bash
find gitops -name kustomization.yaml -printf '%h\n' | while read -r dir; do
  kubectl kustomize "$dir" >/dev/null
done

find gitops -name '*.yaml' ! -name kustomization.yaml -print0 \
  | xargs -0 kubeconform -strict -ignore-missing-schemas -summary \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
