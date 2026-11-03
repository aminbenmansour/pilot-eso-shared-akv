# Plain Kustomize example

The baseline deployment: no GitOps controller, just `kubectl` and Kustomize.
It is the same application configuration the `argocd` and `flux` examples
deploy, kept here so the multi-environment layout can be read and applied on its
own.

## Layout

```
gitops/plain/
  manifests/
    platform/namespace.yaml      # glitchtip namespace
    apps/glitchtip/base/         # env-agnostic SecretStore + ExternalSecret
    environments/<env>/          # per-environment vault URL and refresh
```

The overlay only patches the values that differ per environment, so the base
stays identical across dev, staging and prod.

## Environments

| Environment | Key Vault | Refresh |
|-------------|-----------|---------|
| dev | `https://kv-myproject-dev.vault.azure.net` | 5m |
| staging | `https://kv-myproject-staging.vault.azure.net` | 15m |
| prod | `https://kv-myproject-prod.vault.azure.net` | 1h |

Each environment uses its own Key Vault. The Terraform module only grants access
to secrets prefixed with `<app>--`, so per-vault separation means a dev identity
cannot read staging or production secrets.

## Deploy

```bash
./gitops/plain/deploy.sh dev --dry-run   # render only
./gitops/plain/deploy.sh dev
```

The script installs External Secrets Operator with Helm (pinned `2.14.0`), then
applies the platform namespace and the environment overlay:

```bash
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --version 2.14.0 --set installCRDs=true --wait

kubectl apply -f gitops/plain/manifests/platform/namespace.yaml
kubectl apply -k gitops/plain/manifests/environments/dev
```

Repeat with `staging` and `prod`, each against its own cluster. After a change,
re-running the same command is enough: `kubectl apply` is idempotent and ESO
refreshes the secret on its interval.

## Bootstrap order

1. Create the cluster for the environment.
2. Run Terraform for the application: managed identity, federated credential,
   Key Vault RBAC and the annotated service account.
3. Run `deploy.sh` for the environment.

Step 2 must precede step 3 because the module creates the service account inside
the namespace. Until it completes, the `SecretStore` reports an error and ESO
retries.

## Relationship to the other examples

`argocd/` and `flux/` contain the same `manifests/` tree. The three examples are
independent on purpose so each one can be copied, read or deleted without the
others. Keep the copies in sync; CI checks that they still match.

## Notes

- The workload identity service account is Terraform-managed. It is deliberately
  absent from these manifests; see `gitops/README.md`.
- Secret keys must keep the `<app>--` prefix, otherwise the Key Vault role
  assignment does not allow reading them.
