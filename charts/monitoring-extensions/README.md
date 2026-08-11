# monitoring-extensions

Custom Grafana dashboards layered on top of an **existing** `kube-prometheus-stack` release.

This is a **companion chart, not an umbrella chart** — it declares no dependency on
`kube-prometheus-stack` and is deployed as a second `HelmRelease` gated on the first. Upstream stays
a plain upstream release that can be bumped on its own schedule, and deleting this release leaves
that stack fully functional. See [`spec/specification.md`](../../spec/specification.md) §6.

The chart owns no Deployment, Service, PVC, or workload of any kind. It ships ConfigMaps that an
already-running Grafana sidecar reads.

## How dashboards get in

Every file matching `dashboards/*.json` becomes one ConfigMap carrying the label the Grafana sidecar
watches. **Adding a dashboard is dropping a file in that folder** — no template edit (spec §4.3):

1. Build it in Grafana, export **"for sharing externally"**.
2. Apply the authoring rules below.
3. Save as `dashboards/<area>-<name>.json`.
4. Open a PR. CI validates the JSON and renders the ConfigMap.

### Authoring rules (spec §3.2)

Dashboards exported from the Grafana UI are **not** directly usable. Rules 1–3 are enforced
mechanically by `hack/validate-dashboards.sh`:

| # | Rule | Why |
|---|---|---|
| 1 | `"id"` must be `null` | an export carries the source instance's numeric id, which collides on import |
| 2 | `"uid"` set, stable, unique — `k8se-<area>-<name>` | it is the permalink; changing it orphans every saved link and annotation |
| 3 | No hardcoded datasource UID | use `${datasource}` or the stack's known UID `prometheus`; a foreign UID renders every panel as "datasource not found" |
| 4 | No hardcoded `namespace`, `pod`, `cluster` | use `label_values()` variables so one dashboard serves every cluster |
| 5 | Relative `"time"` (`now-6h` → `now`) | absolute timestamps freeze the dashboard at export time |
| 6 | `"refresh"` ≥ scrape interval | shorter produces load, not resolution |

`"editable": true` is fine — the sidecar's `provider.allowUiUpdates` is `false`, so UI edits are
discarded on restart. That is deliberate: the file is the source of truth.

## Values

| Key | Default | Description |
|---|---|---|
| `dashboards.enabled` | `true` | Toggle dashboards independently of alerting/rules, because `dev` can take dashboards without an in-cluster Alertmanager (spec §5.3). |
| `dashboards.label` | `grafana_dashboard` | Label the sidecar watches. Must match `grafana.sidecar.dashboards.label` upstream. |
| `dashboards.labelValue` | `"1"` | Must match `grafana.sidecar.dashboards.labelValue` upstream. A string, not a number. |
| `dashboards.folder` | `""` | Grafana folder name. Empty means the General folder. **See the caveat below.** |
| `dashboards.folderAnnotation` | `grafana_folder` | Annotation key carrying the folder name. |
| `dashboards.extraLabels` | `{}` | Extra labels on dashboard ConfigMaps only. |
| `namespaceOverride` | `""` | Target namespace; empty means the release namespace. Never hardcode `monitoring` (spec §5.3). |
| `commonLabels` | `{}` | Labels applied to every rendered object. |
| `commonAnnotations` | `{}` | Annotations applied to every rendered object. |
| `nameOverride` / `fullnameOverride` | `""` | Standard Helm naming overrides. |
| `rules.enabled` | `true` | Toggle the `PrometheusRule` independently of dashboards. |
| `rules.interval` | `""` | Rule group evaluation interval; empty means Prometheus' global default. |
| `rules.additionalRuleLabels` | `{}` | Extra labels on every rule — routing will key off these. |
| `rules.recording.podMemoryRatio.enabled` | `true` | The memory-vs-limit recording rule. |
| `rules.alerts.podMemoryNearLimit.enabled` | `true` | The alert built on that series. |
| `rules.alerts.podMemoryNearLimit.threshold` | `0.9` | Fraction of the memory limit. |
| `rules.alerts.podMemoryNearLimit.for` | `15m` | How long the condition must hold. |
| `rules.alerts.podMemoryNearLimit.severity` | `warning` | `critical`, `warning` or `info`. |
| `rules.alerts.podMemoryNearLimit.runbookUrl` | `""` | Emitted as `runbook_url` when set. |

The defaults for `label` and `labelValue` are the verified `kube-prometheus-stack` 87.16.1 defaults,
so **dashboards work with no change to the upstream release** (spec §3.1).

### The folder caveat

`dashboards.folder` is a no-op on its own. Grafana's sidecar places every dashboard in the General
folder unless the **upstream** release also sets *both*:

```yaml
grafana:
  sidecar:
    dashboards:
      folderAnnotation: grafana_folder
      provider:
        foldersFromFilesStructure: true
```

Either alone does nothing (spec §3.1, §3.5). This is the only upstream change dashboards require, and
it is optional.

## Local development

```bash
./ci-tools/install-tools.sh                          # once: kubeconform + helm-unittest
./ci-tools/validate-chart.sh monitoring-extensions   # the whole charts-ci gate
```

Individual steps, if you want them:

```bash
helm lint charts/monitoring-extensions
./ci-tools/render-chart.sh monitoring-extensions     # every values profile
./ci-tools/validate-dashboards.sh charts/monitoring-extensions
helm unittest charts/monitoring-extensions
```

`ci/*-values.yaml` files are extra values profiles that CI renders in addition to `values.yaml` —
`ci/folders-values.yaml` exercises the folder-annotation path the defaults leave off.

## Versioning

`Chart.yaml`'s `version` is `0.0.0` in git and is **written by CI** from the tag
`monitoring-extensions-x.y.z` on merge to `main`. Do not bump it by hand (spec §2.3). `appVersion` is
`"0"` because the chart ships no image.

## Rules

One recording rule and one alert, as a worked example of the §3.4 contract. They ship as a single
`PrometheusRule`. **No upstream change is needed** — the current release sets
`ruleSelectorNilUsesHelmValues: false`, leaving `ruleSelector` and `ruleNamespaceSelector` empty, so
every `PrometheusRule` in every namespace is discovered. Verified against the live `Prometheus` CR.

**Recording:** `k8se_namespace_pod:container_memory_working_set_bytes:ratio_limit` — working set
divided by memory limit, per pod. Recorded rather than repeated because the join is comparatively
expensive and both the alert and the Workloads dashboard want it. Naming follows the Prometheus
`level:metric:operations` convention, prefixed `k8se_` so custom series stand out.

**Alert:** `K8sePodMemoryNearLimit` — fires when that ratio exceeds `threshold` (0.9) for `for`
(15m), with `severity: warning`. Pods with **no** memory limit produce no series and therefore never
fire, which is intended: a pod with no limit has no limit to approach.

These are deliberately workload-level. Upstream already ships ~100 cluster and node rules and
duplicating them is noise (spec §3.4).

### Alerts fire, but nothing delivers them yet

The alerts are visible in Prometheus and in Alertmanager's UI with no routing configured. **Delivery
is not implemented** — that is `AlertmanagerConfig` (spec §3.3), still to be built.

When it is, note that cluster-wide routing additionally requires
`alertmanagerConfigMatcherStrategy.type: None` upstream. Without it the operator injects a
`namespace="monitoring"` matcher into every route, so alerts from every other namespace — which is
nearly all of them, including these — silently never match (spec §3.3.1).
