# Flux CD setup

Flux runs inside every cluster; there is no management cluster and no cluster
secrets to maintain. Each cluster directory is the entry point for that
environment and points at the matching overlay.

## Prerequisites

- `flux` CLI and credentials for the target cluster.
- The repository already exists (Flux bootstrap pushes to it).

## Bootstrap

Run once per cluster:

```bash
# dev
flux bootstrap github \
  --owner=aminbenmansour \
  --repository=pilot-eso-shared-akv \
  --branch=main \
  --path=gitops/flux/clusters/dev \
  --personal

# repeat with --path=gitops/flux/clusters/staging and .../prod
```

Bootstrap commits `gotk-sync.yaml` and `kustomization.yaml` into the cluster
directory. They are intentionally not part of this example because they contain
the generated sync configuration and must be created against the real
repository. The `flux-system` Kustomization then reconciles everything in that
directory.

The repository is public; no deploy key or token secret is needed at runtime.

## What gets reconciled

| Kustomization | Path | Purpose |
|---------------|------|---------|
| `flux-system` (bootstrap) | `gitops/flux/clusters/<env>` | applies the cluster entry point |
| `platform` | `gitops/platform` | `glitchtip` namespace |
| `external-secrets` | `gitops/flux/platform` | ESO Helm chart and its CRDs |
| `apps` | `gitops/environments/<env>` | `SecretStore` and `ExternalSecret` |

Ordering comes from `dependsOn`: `external-secrets` waits for `platform`, and
`apps` waits for `external-secrets`. The `external-secrets` Kustomization uses a
`healthChecks` entry for the `HelmRelease`, so `apps` only starts once the
operator is ready.

## Health checks

`apps` uses `healthCheckExprs` with CEL instead of `wait: true` (setting `wait`
would ignore the expressions):

```yaml
current: size(status.conditions) > 0 && status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
failed: size(status.conditions) > 0 && status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
```

A failing `ExternalSecret` therefore marks the `Kustomization` as not ready
instead of silently succeeding. Adjust the condition type if you use a different
ESO version.

## Promotion

- Dev and staging reconcile automatically after a merge.
- Production is gated by pull request review and branch protection: the `apps`
  Kustomization applies `gitops/environments/prod` once the change lands on
  `main`. If you need an explicit approval step in the cluster, suspend the
  Kustomization and resume it after sign-off:

  ```bash
  flux suspend kustomization apps
  flux resume kustomization apps
  ```

- Do not use one branch per environment; the environment directory already makes
  the target explicit and keeps a single revision history.

## Drift

Every `interval`, kustomize-controller performs a server-side apply dry-run and
corrects drift. Use `spec.ignore` with JSON pointers if another controller owns
a field you do not want reverted; do not add the Terraform-managed service
account to an overlay.

## Debugging

```bash
flux get kustomizations -A
flux get helmreleases -A
flux reconcile kustomization apps --with-source
kubectl -n glitchtip get externalsecret glitchtip-env -o yaml
```

## Notes

- The ESO chart is pinned in `gitops/flux/platform/external-secrets.yaml`
  (currently `2.14.0`). Bump it deliberately through a pull request.
- The workload identity service account is Terraform-managed; see
  `gitops/README.md`.
