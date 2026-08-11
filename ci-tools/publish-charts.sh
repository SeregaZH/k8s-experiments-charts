#!/usr/bin/env bash
# Versions, packages and publishes charts as OCI artifacts, then tags the repo
# (spec §2.3, §4.1 steps 6-8).
#
#   ci-tools/publish-charts.sh <chart> [chart ...]
#
# Environment:
#   OCI_REGISTRY   default oci://ghcr.io/seregazh/charts
#   GHCR_USER      registry user (skip login if unset)
#   GHCR_TOKEN     registry token
#   BUMP           override the bump level; default reads the commit message
#   DRY_RUN        1 = do everything except push and tag
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -gt 0 ] || die "usage: publish-charts.sh <chart> [chart ...]"

require_cmd helm
here="$(dirname "${BASH_SOURCE[0]}")"

OCI_REGISTRY="${OCI_REGISTRY:-oci://ghcr.io/seregazh/charts}"
DRY_RUN="${DRY_RUN:-0}"

cd "$REPO_ROOT"

if [ "$DRY_RUN" = "1" ]; then
  warn "DRY_RUN=1 — will not push or tag"
elif [ -n "${GHCR_USER:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
  registry_host="${OCI_REGISTRY#oci://}"
  registry_host="${registry_host%%/*}"
  group "registry login ${registry_host}"
  printf '%s' "$GHCR_TOKEN" | helm registry login "$registry_host" -u "$GHCR_USER" --password-stdin
  endgroup
else
  die "GHCR_USER/GHCR_TOKEN not set (use DRY_RUN=1 to test without publishing)"
fi

if [ "$DRY_RUN" != "1" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

for chart in "$@"; do
  dir="$(chart_dir "$chart")"
  group "publish ${chart}"

  version="$("${here}/next-version.sh" "$chart" "${BUMP:-}")"
  tag="${chart}-${version}"

  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    die "tag ${tag} already exists — refusing to republish"
  fi
  info "version: ${version}  (tag ${tag})"

  # Write the version into Chart.yaml in the workspace only. The git tag is the
  # source of truth (spec §2.3), so this is never committed back to main — that
  # would add a bot commit to every merge for no benefit.
  #
  # Restore from a copy rather than `git checkout --`: a chart added in this very
  # merge is untracked from git's point of view, and checkout would fail on it.
  backup="${workdir}/${chart}.Chart.yaml.orig"
  cp "${dir}/Chart.yaml" "$backup"
  sed -i -E "s/^version:.*/version: ${version}/" "${dir}/Chart.yaml"
  grep -E '^(name|version|appVersion):' "${dir}/Chart.yaml" | sed 's/^/    /'

  helm package "$dir" -d "$workdir" >/dev/null
  cp "$backup" "${dir}/Chart.yaml"   # leave the tree as we found it

  package="${workdir}/${chart}-${version}.tgz"
  [ -f "$package" ] || die "expected package at ${package}"
  info "packaged: $(basename "$package")"

  if [ "$DRY_RUN" = "1" ]; then
    info "dry run — skipping push and tag"
  else
    helm push "$package" "$OCI_REGISTRY"
    # Tag only after a successful push, so tags and registry never disagree.
    # This is why publishing precedes tagging rather than following the literal
    # step order in spec §4.1: a tag with no artifact behind it is worse than a
    # published artifact whose tag lands a second later.
    git tag -a "$tag" -m "$tag"
    git push origin "$tag"
    info "published ${chart} ${version}"
  fi
  endgroup
done
