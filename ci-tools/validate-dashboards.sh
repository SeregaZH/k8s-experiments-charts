#!/usr/bin/env bash
# Mechanical enforcement of dashboard authoring rules 1-3 from spec §3.2, which
# spec §5.2 lists as a charts-ci check:
#
#   1. id must be null          — an export carries the source instance's id
#   2. uid set and unique       — it is the permalink
#   3. no hardcoded datasource  — a foreign uid renders every panel as an error
#
#   ci-tools/validate-dashboards.sh [chart-dir ...]
#
# Defaults to every chart under charts/ that has a dashboards/ directory.
# Duplicate uids are detected across all charts checked in one run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd jq

cd "$REPO_ROOT"

fail=0
note() { printf '  %-6s %s\n' "$1" "$2"; }

dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  mapfile -t dirs < <(find charts -maxdepth 2 -type d -name dashboards -printf '%h\n' | sort)
fi

declare -A seen_uid

for chart in "${dirs[@]}"; do
  echo "chart: ${chart}"
  shopt -s nullglob
  files=("${chart}"/dashboards/*.json)
  shopt -u nullglob

  if [ ${#files[@]} -eq 0 ]; then
    note "skip" "no dashboards"
    continue
  fi

  for f in "${files[@]}"; do
    name="$(basename "$f")"
    file_ok=1

    if ! jq empty "$f" 2>/dev/null; then
      note "FAIL" "${name}: not valid JSON"; fail=1; continue
    fi

    # Rule 1
    if [ "$(jq '.id' "$f")" != "null" ]; then
      note "FAIL" "${name}: .id must be null (got $(jq -c '.id' "$f"))"; fail=1; file_ok=0
    fi

    # Rule 2
    uid="$(jq -r '.uid // ""' "$f")"
    if [ -z "$uid" ]; then
      note "FAIL" "${name}: .uid must be set"; fail=1; file_ok=0
    else
      if [ -n "${seen_uid[$uid]:-}" ]; then
        note "FAIL" "${name}: duplicate uid '${uid}' (also ${seen_uid[$uid]})"; fail=1; file_ok=0
      fi
      seen_uid[$uid]="$name"
      # Convention from spec §3.2: k8se-<area>-<name>
      if [[ ! "$uid" =~ ^k8se-[a-z0-9]+-[a-z0-9-]+$ ]]; then
        note "warn" "${name}: uid '${uid}' does not match k8se-<area>-<name>"
      fi
    fi

    # Rule 3: every prometheus datasource ref must be a template variable
    # (${...}) or the stack's known UID 'prometheus'.
    bad="$(jq -r '
      [ .. | objects
        | select(has("uid") and has("type"))
        | select(.type == "prometheus")
        | .uid ]
      | unique
      | map(select(startswith("${") | not))
      | map(select(. != "prometheus"))
      | .[]' "$f")"
    if [ -n "$bad" ]; then
      note "FAIL" "${name}: hardcoded datasource uid(s): $(echo "$bad" | tr '\n' ' ')"; fail=1; file_ok=0
    fi

    [ "$file_ok" -eq 1 ] && note "ok" "${name}  (uid=${uid})"
  done
done

if [ "$fail" -ne 0 ]; then
  die "dashboard validation failed"
fi
echo "  dashboard validation passed"
