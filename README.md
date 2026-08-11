# k8s-experiments-charts

Helm charts for customized deployment of different components to k8s clusters.

A **monorepo of Helm charts**: one folder → one chart → one published OCI artifact. It contains no
cluster configuration and no Flux resources — it *publishes* charts; the sibling repo
`k8s-workload-deploy` *consumes* them.

Design is specified before implementation. See [`spec/specification.md`](spec/specification.md).

## Charts

| Chart | Status | Purpose |
|---|---|---|
| [`monitoring-extensions`](charts/monitoring-extensions/) | dashboards + rules implemented; alert delivery pending | Custom Grafana dashboards and Alertmanager configuration layered on an existing `kube-prometheus-stack` release |

## Local development

CI logic lives in [`ci-tools/`](ci-tools/) as ordinary scripts, not inline workflow steps, so the
exact checks a pull request runs also run on a laptop:

```bash
./ci-tools/install-tools.sh                            # kubeconform + helm-unittest, pinned versions
./ci-tools/validate-chart.sh monitoring-extensions     # the whole charts-ci gate
./ci-tools/validate-charts.sh                          # every chart
```

| Script | Does |
|---|---|
| `install-tools.sh` | Installs the pinned toolchain. Idempotent. |
| `discover-charts.sh` | Lists charts as JSON, for the CI matrix. |
| `select-charts.sh` | Chooses charts to publish: explicit name, else changed set. Space-separated. |
| `detect-changed-charts.sh` | Charts touched between two commits. |
| `render-chart.sh` | Renders every values profile (`values.yaml` + `ci/*-values.yaml`). |
| `validate-chart.sh` | lint → render → kubeconform → dashboards → promtool → unittest. |
| `validate-charts.sh` | `validate-chart.sh` over several charts. |
| `validate-dashboards.sh` | Dashboard authoring rules 1–3 (spec §3.2). |
| `extract-rule-groups.py` | Lifts rule groups out of `PrometheusRule` CRs for promtool. |
| `next-version.sh` | Next SemVer from this chart's own tags. |
| `publish-charts.sh` | Version → package → push OCI → tag. Honours `DRY_RUN=1`. |

## Publication flow

Two triggers that must not be confused (spec §4.1):

| Trigger | Workflow | Does | Publishes? |
|---|---|---|---|
| Pull request | [`charts-ci`](.github/workflows/charts-ci.yml) | lint, render, schema-validate, unit test | **No** |
| Merge to `main` | [`charts-publish`](.github/workflows/charts-publish.yml) | version bump, tag, push OCI | **Yes** |

Both also accept `workflow_dispatch` — `charts-ci` to validate without a PR, `charts-publish` to
re-publish a named chart or rehearse with `dry_run` (which defaults to **true** for manual runs, so
a stray click cannot publish).

Every chart is versioned **independently** — a change to one never bumps another. The version lives
in a git tag `<chart>-<major>.<minor>.<patch>` (e.g. `monitoring-extensions-0.1.0`), which is the
single source of truth; `Chart.yaml`'s `version` stays `0.0.0` in git and is written from the tag at
package time. The bump level comes from the merge commit message: `#major`, `#minor`, otherwise
patch. Charts publish as OCI artifacts to `ghcr.io/seregazh/charts`. See spec §2.3.

Publishing happens **before** tagging, so a failed push never leaves a tag with no artifact behind
it. This inverts the literal step order in spec §4.1 and matches `infrastructure-experiments`
`modules-publish`.
