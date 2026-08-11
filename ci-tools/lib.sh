#!/usr/bin/env bash
# Shared helpers for the ci-tools scripts. Sourced, not executed.
#
# Everything here is plain bash with no GitHub Actions dependency, so every
# script runs identically on a laptop and on a runner.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Group markers collapse in the Actions log and are harmless locally.
group()    { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$*"; else echo "==> $*"; fi; }
endgroup() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi; }
info()     { printf '  %s\n' "$*"; }
warn()     { printf '  WARN  %s\n' "$*" >&2; }
die()      { printf '  ERROR %s\n' "$*" >&2; exit 1; }

# Emit a name=value pair to $GITHUB_OUTPUT when running in Actions, and always
# echo it so local runs are useful too.
emit() {
  local name="$1" value="$2"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  echo "${name}=${value}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required tool '$1' not found on PATH"
}

chart_dir() {
  local chart="$1"
  local dir="${REPO_ROOT}/charts/${chart}"
  [ -f "${dir}/Chart.yaml" ] || die "no chart at charts/${chart}"
  echo "$dir"
}
