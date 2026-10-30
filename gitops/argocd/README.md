# Argo CD setup

Argo CD runs on a management cluster and deploys to one cluster per
environment. The environment isolation lives in `gitops/environments/<env>`;
this directory only wires those paths to the clusters.

## Prerequisites

- Argo CD installed on the management cluster, with `kubectl` access to the
  `argocd` namespace.
- One cluster per environment, registered with labels.

```bash
argocd cluster add aks-myproject-dev \
  --name aks-myproject-dev \
  --label env=dev \
  --label eso-example=true
```

Use the same labels for staging and prod (`env=staging`, `env=prod`). The label
selection is what makes the ApplicationSets multi-cluster: no API server URLs
are stored in this repository.

## Apply

```bash
kubectl apply -k gitops/argocd
```

This creates:

| Resource | Purpose |
|----------|---------|
| `AppProject/eso-platform` | namespace and ESO installation, with the cluster-scoped permissions the chart needs |
| `AppProject/eso-apps` | `SecretStore`/`ExternalSecret` only, no cluster-scoped resources |
| `ApplicationSet/eso-platform-namespace` | `gitops/platform` on every labelled cluster |
| `ApplicationSet/eso-platform-external-secrets` | ESO Helm chart on every labelled cluster |
| `ApplicationSet/eso-apps-auto` | dev and staging overlays, automated sync |
| `ApplicationSet/eso-apps-prod` | prod overlay, manual sync |

## Ordering

The ApplicationSets are independent, so on a fresh cluster the application syncs
may run before the ESO CRDs exist. The app template sets
`SkipDryRunOnMissingResource=true` and a retry backoff, so Argo converges once the
operator is installed. If you need strict ordering, gate it with an app-of-apps
and `argocd.argoproj.io/sync-wave` annotations on the `Application` objects.

## Production promotion

`eso-apps-prod` intentionally has no `automated` block. Merging a change to
`gitops/environments/prod` leaves the application `OutOfSync` until someone
approves and syncs it:

```bash
argocd app sync aks-myproject-prod-glitchtip
```

Dev and staging prune and self-heal automatically.

## ExternalSecret health

Argo CD has no built-in health check for ESO resources. Add this to the
`argocd-cm` ConfigMap (`configs.cm` when using the Helm chart) so a failing
`ExternalSecret` shows as `Degraded` instead of `Healthy`:

```lua
resource.customizations.health.external-secrets.io_ExternalSecret: |
  hs = {}
  if obj.status ~= nil and obj.status.conditions ~= nil then
    for i, condition in ipairs(obj.status.conditions) do
      if condition.type == "Ready" then
        hs.status = condition.status == "True" and "Healthy" or "Degraded"
        hs.message = condition.message or condition.reason
        return hs
      end
    end
  end
  hs.status = "Progressing"
  hs.message = "Waiting for ExternalSecret"
  return hs
```

Do the same for `ExternalSecret` resources in other repositories if they use the
same operator.

## Notes

- The ESO chart version is pinned in `platform/external-secrets-applicationset.yaml`
  (currently `2.14.0`). Bump it deliberately through a pull request.
- `targetRevision` points at `main`. Pin to a tag or commit SHA if you need
  reproducible rollbacks independent of the Git history.
- The workload identity service account is Terraform-managed. Do not add it to an
  overlay; see `gitops/README.md`.
