#!/usr/bin/env bash
# Computes the next SemVer for a chart from its own git tags, so charts version
# independently: a change to one never bumps another (spec §2.3).
#
#   ci-tools/next-version.sh <chart> [major|minor|patch]
#
# The bump level defaults to reading the HEAD commit message: `#major`, `#minor`,
# otherwise patch. Prints the bare version, e.g. 0.2.0.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

chart="${1:?usage: next-version.sh <chart> [bump]}"
bump="${2:-}"

cd "$REPO_ROOT"

if [ -z "$bump" ]; then
  message="$(git log -1 --pretty=%B)"
  case "$message" in
    *'#major'*) bump=major ;;
    *'#minor'*) bump=minor ;;
    *)          bump=patch ;;
  esac
fi

# Tags for THIS chart only. `-v:refname` sorts by version, so the newest wins
# even when 0.10.0 exists alongside 0.9.0.
latest="$(git tag -l "${chart}-*" --sort=-v:refname | head -n1)"

if [ -z "$latest" ]; then
  # First release of a new chart.
  echo "0.1.0"
  exit 0
fi

current="${latest#"${chart}-"}"
IFS=. read -r major minor patch <<< "$current"

case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *)     die "unknown bump level '${bump}'" ;;
esac

echo "${major}.${minor}.${patch}"
