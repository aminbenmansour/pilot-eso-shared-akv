#!/usr/bin/env bash
#
# Apply the Argo CD bootstrap for this example (AppProjects + ApplicationSets).
# Argo CD must already be installed in the `argocd` namespace.
#
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gitops/argocd/deploy.sh [--dry-run]

Options:
  --dry-run   server-side dry run, no changes are persisted
  -h, --help  show this help

Environment:
  KUBECTL     kubectl binary to use (default: kubectl)

Prerequisites:
  - Argo CD installed on the management cluster
  - every target cluster registered with env=<dev|prod> and
    eso-example=true, for example:
      argocd cluster add aks-myproject-dev --name aks-myproject-dev \
        --label env=dev --label eso-example=true

The ApplicationSets then reconcile gitops/argocd/manifests on each cluster.
EOF
}

kubectl_bin="${KUBECTL:-kubectl}"
dry_run=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

command -v "$kubectl_bin" >/dev/null 2>&1 || {
  echo "error: $kubectl_bin not found in PATH" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bootstrap="$repo_root/gitops/argocd/bootstrap"

cmd=("$kubectl_bin" apply -k "$bootstrap")
if [ "$dry_run" = true ]; then
  cmd+=(--dry-run=server)
fi

echo "+ ${cmd[*]}"
"${cmd[@]}"
