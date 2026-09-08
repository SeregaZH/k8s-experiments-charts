# k8s-experiments-charts

Helm charts for customized deployment of different components to k8s clusters.

A **monorepo of Helm charts**: one folder → one chart → one published OCI artifact. It contains no
cluster configuration and no Flux resources — it *publishes* charts; the sibling repo
`k8s-workload-deploy` *consumes* them.

Design is specified before implementation. Each chart carries its own specification beside it — see
[`charts/monitoring-extensions/spec/specification.md`](charts/monitoring-extensions/spec/specification.md).

## Charts

| Chart | Status | Purpose |
|---|---|---|
| [`monitoring-extensions`](charts/monitoring-extensions/) | dashboards + rules implemented; alert delivery pending | Custom Grafana dashboards and Alertmanager configuration layered on an existing `kube-prometheus-stack` release |

## Local development

CI logic lives in the shared [`ci-tools`](https://github.com/SeregaZH/ci-tools)
submodule as ordinary scripts, not inline workflow steps, so the exact checks a
pull request runs also run on a laptop. Once per clone:

```bash
git submodule update --init
```

then:

```bash
./ci-tools/monorepo/install-tools.sh                            # kubeconform + helm-unittest, pinned versions
./ci-tools/monorepo/validate-chart.sh monitoring-extensions     # the whole charts-ci gate
./ci-tools/monorepo/validate-charts.sh                          # every chart
```

Everything this repo has to say about itself — registry, tag scheme, tool
versions — is in [`.ci-tools.env`](.ci-tools.env), which the scripts source
themselves. Nothing is repeated in the workflows.

| Script | Does |
|---|---|
| `ci-tools/monorepo/install-tools.sh` | Installs the pinned toolchain. Idempotent. |
| `ci-tools/monorepo/discover-charts.sh` | Lists charts as JSON, for the CI matrix. |
| `ci-tools/monorepo/select-charts.sh` | Chooses charts to publish: explicit name, else changed set. Space-separated. |
| `ci-tools/monorepo/detect-changed-charts.sh` | Charts touched between two commits. |
| `ci-tools/monorepo/render-chart.sh` | Renders every values profile (`values.yaml` + `ci/*-values.yaml`). |
| `ci-tools/monorepo/validate-chart.sh` | lint → render → kubeconform → promtool → unittest → `ci/checks/`. |
| `ci-tools/monorepo/validate-charts.sh` | `validate-chart.sh` over several charts. |
| `ci-tools/monorepo/extract-rule-groups.py` | Lifts rule groups out of `PrometheusRule` CRs for promtool. |
| `ci-tools/monorepo/next_version.py` | Next SemVer from this chart's own tags. |
| `ci-tools/monorepo/publish-charts.sh` | Version → package → push OCI → tag. Honours `DRY_RUN=1`. |
| `ci/checks/validate-dashboards.sh` | **This repo's own.** Dashboard authoring rules 1–3 (spec §3.2). |

`ci/checks/` is the extension point: `validate-chart.sh` runs every executable
in it with the chart directory, so a rule that is this repository's business
stays here instead of leaking into the shared repo.

To bump the pinned ci-tools:

```bash
git submodule update --remote ci-tools && git commit ci-tools -m "Bump ci-tools"
```

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
