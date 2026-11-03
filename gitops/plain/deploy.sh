#!/usr/bin/env bash
#
# Deploy the plain Kustomize example for one environment.
# Installs External Secrets Operator with Helm, then applies the namespace and
# the environment overlay.
#
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gitops/plain/deploy.sh <dev|staging|prod> [--dry-run] [--skip-eso]

Options:
  --dry-run    render everything, do not change the cluster
  --skip-eso   do not install External Secrets Operator
  -h, --help   show this help

Environment:
  KUBECTL            kubectl binary (default: kubectl)
  HELM               helm binary (default: helm)
  ESO_CHART_VERSION  ESO chart version (default: 2.14.0)
  ESO_NAMESPACE      operator namespace (default: external-secrets)

Prerequisites:
  - kubectl and helm in PATH, with a kubeconfig for the target cluster
  - Terraform already created the workload identity service account
EOF
}

env_name="${1:-}"
if [ -z "$env_name" ] || [ "${env_name#-}" != "$env_name" ]; then
  usage >&2
  exit 2
fi
shift

case "$env_name" in
  dev|staging|prod) ;;
  *)
    echo "error: unknown environment '$env_name' (expected dev, staging or prod)" >&2
    exit 2
    ;;
esac

dry_run=false
skip_eso=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --skip-eso) skip_eso=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

kubectl_bin="${KUBECTL:-kubectl}"
helm_bin="${HELM:-helm}"
eso_version="${ESO_CHART_VERSION:-2.14.0}"
eso_namespace="${ESO_NAMESPACE:-external-secrets}"

command -v "$kubectl_bin" >/dev/null 2>&1 || {
  echo "error: $kubectl_bin not found in PATH" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifests="$repo_root/gitops/plain/manifests"

if [ "$skip_eso" = false ]; then
  command -v "$helm_bin" >/dev/null 2>&1 || {
    echo "error: $helm_bin not found in PATH (use --skip-eso to skip the operator)" >&2
    exit 1
  }

  "$helm_bin" repo add external-secrets https://charts.external-secrets.io --force-update >/dev/null

  if [ "$dry_run" = true ]; then
    echo "+ helm template external-secrets external-secrets/external-secrets --version $eso_version"
    "$helm_bin" template external-secrets external-secrets/external-secrets \
      --namespace "$eso_namespace" \
      --version "$eso_version" \
      --set installCRDs=true >/dev/null
  else
    echo "+ helm upgrade --install external-secrets external-secrets/external-secrets --namespace $eso_namespace --version $eso_version"
    "$helm_bin" upgrade --install external-secrets external-secrets/external-secrets \
      --namespace "$eso_namespace" \
      --create-namespace \
      --version "$eso_version" \
      --set installCRDs=true \
      --wait
  fi
fi

kubectl_flags=(--dry-run=client)
[ "$dry_run" = true ] || kubectl_flags=()

echo "+ $kubectl_bin apply -f $manifests/platform/namespace.yaml"
"$kubectl_bin" apply -f "$manifests/platform/namespace.yaml" "${kubectl_flags[@]}"

echo "+ $kubectl_bin apply -k $manifests/environments/$env_name"
"$kubectl_bin" apply -k "$manifests/environments/$env_name" "${kubectl_flags[@]}"
