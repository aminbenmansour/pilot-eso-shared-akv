#!/usr/bin/env bash
#
# Bootstrap Flux for one environment of this example.
# Flux installs itself into the cluster and commits its sync configuration to
# gitops/flux/clusters/<env>.
#
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gitops/flux/deploy.sh <dev|staging|prod> [--dry-run]

Options:
  --dry-run   print the bootstrap command instead of running it
  -h, --help  show this help

Environment:
  FLUX_BIN      flux binary to use (default: flux)
  GITHUB_OWNER  repository owner (default: aminbenmansour)
  GITHUB_REPO   repository name (default: pilot-eso-shared-akv)
  GITHUB_BRANCH branch to commit to (default: main)

Prerequisites:
  - flux CLI installed and a kubeconfig pointing at the target cluster
  - the GitHub token in the environment or the flux prompt (repo scope)

Run it once per environment cluster. The --personal flag is used because the
repository lives under a personal GitHub account; drop it for an organization.
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
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

flux_bin="${FLUX_BIN:-flux}"
owner="${GITHUB_OWNER:-aminbenmansour}"
repo="${GITHUB_REPO:-pilot-eso-shared-akv}"
branch="${GITHUB_BRANCH:-main}"

cmd=(
  "$flux_bin" bootstrap github
  --owner="$owner"
  --repository="$repo"
  --branch="$branch"
  --path="gitops/flux/clusters/${env_name}"
  --personal
  --reconcile
)

if [ "$dry_run" = true ]; then
  echo "${cmd[*]}"
  exit 0
fi

command -v "$flux_bin" >/dev/null 2>&1 || {
  echo "error: $flux_bin not found in PATH" >&2
  exit 1
}
command -v kubectl >/dev/null 2>&1 || {
  echo "error: kubectl not found in PATH" >&2
  exit 1
}

echo "+ ${cmd[*]}"
"${cmd[@]}"
