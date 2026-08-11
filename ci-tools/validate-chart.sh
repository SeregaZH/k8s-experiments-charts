#!/usr/bin/env bash
# The full charts-ci gate for one chart (spec §5.2). Run it locally to get
# exactly what the pull request will run:
#
#   ci-tools/validate-chart.sh monitoring-extensions
#
# | Check           | Tool          | Catches                                    |
# |-----------------|---------------|--------------------------------------------|
# | Chart lint      | helm lint     | malformed chart metadata                   |
# | Render          | helm template | template errors, bad indentation           |
# | Schema          | kubeconform   | invalid AlertmanagerConfig/PrometheusRule  |
# | Dashboard JSON  | jq            | non-null id, missing/dup uid, hardcoded ds |
# | Rule syntax     | promtool      | invalid PromQL                             |
# | Unit tests      | helm-unittest | label/annotation regressions               |
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

chart="${1:?usage: validate-chart.sh <chart>}"
dir="$(chart_dir "$chart")"
here="$(dirname "${BASH_SOURCE[0]}")"

require_cmd helm
require_cmd jq

group "helm lint ${chart}"
helm lint "$dir"
endgroup

rendered="$("${here}/render-chart.sh" "$chart" | tail -n1)"

group "kubeconform ${chart}"
if ! command -v kubeconform >/dev/null 2>&1; then
  die "kubeconform not found — run ci-tools/install-tools.sh"
fi
# The operator's CRDs are not in kubeconform's default schema set. Without the
# catalog location, AlertmanagerConfig and PrometheusRule are treated as unknown
# and skipped, so an invalid CR would pass silently.
kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "${rendered}"/*.yaml
endgroup

group "dashboard JSON ${chart}"
"${here}/validate-dashboards.sh" "charts/${chart}"
endgroup

group "promtool check rules ${chart}"
rules_dir="${rendered}-rules"
found="$(python3 "${here}/extract-rule-groups.py" "$rendered" "$rules_dir")"
if [ "$found" = "0" ]; then
  # Expected until the chart ships PrometheusRule objects (spec §3.4).
  info "no PrometheusRule rendered — skipping"
elif ! command -v promtool >/dev/null 2>&1; then
  die "promtool not found but ${found} PrometheusRule(s) rendered — install prometheus"
else
  promtool check rules "${rules_dir}"/*.yaml
fi
endgroup

group "helm unittest ${chart}"
if helm plugin list 2>/dev/null | grep -q '^unittest'; then
  helm unittest "$dir"
else
  die "helm-unittest not installed — run ci-tools/install-tools.sh"
fi
endgroup

echo
info "${chart}: all checks passed"
