# self-healing-k8s-pipeline

A self-healing Kubernetes CI/CD + observability demo that runs **free on a local
`kind` cluster**, but is a faithful reconstruction of a real EKS reliability
incident I worked: a pod-scheduling stampede that cascaded into node failures,
plus the Jenkins-on-Kubernetes rebuild that closed an earlier CI/CD gap. I broke
it, fixed it, and built the controls that would have prevented it — and you can
run the whole thing.

## Broke / Fixed / Built (read this first)

- **Broke:** shipped pods with **no resource requests/limits** and a **liveness
  probe doing readiness's job** (1s timeout). Under peak load the scheduler
  over-packed nodes, every pod grabbed memory at once → `MemoryPressure` →
  kubelet evictions → evicted pods rescheduled onto the next node and pushed it
  over → cascading node failures, while the tight liveness probe **killed
  healthy-but-slow pods** into a `CrashLoopBackOff` storm.
- **Fixed:** right-sized requests/limits (scheduler stops overpacking — the
  actual fix), re-pointed/loosened probes (+startupProbe), added a
  **PodDisruptionBudget**, topology spread, and a `maxUnavailable: 0` rollout.
- **Built:** this repo — app, good *and* broken manifests, Prometheus/Grafana +
  the alerts that would have caught it, Terraform, Ansible, GitHub Actions, and a
  Jenkinsfile modeling the EFS-backed Jenkins-on-k8s rebuild.

**Full writeup:** [`docs/BROKE-FIXED-BUILT.md`](docs/BROKE-FIXED-BUILT.md) ·
**Post-mortem:** [`docs/INCIDENT-POSTMORTEM.md`](docs/INCIDENT-POSTMORTEM.md)

## Architecture

```
 GitHub Actions ─┐                         ┌── Grafana ── Prometheus ──┐
 Jenkins/k8s  ───┼─ kubectl apply ─▶ echo ns│        ▲ scrape /metrics  │
   (EFS PVC)     │                   ┌───────┴──────────────────────┐   │
                 │   ingress-nginx ─▶│ Service ─▶ pod x3             │   │
                 │   (:80/:443)      │   ▲HPA  ▲PDB(min2)  startup/  │   │
                 │                   │         live/ready probes     │   │
                 └───────────────────┴───────────────────────────────┘  │
                                          alerts ─▶ Alertmanager ────────┘
```

Full diagram (mermaid) + data flow + prod deltas:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Prerequisites

- Docker (running), `kind`, `kubectl` (v1.31+), `helm`
- Or let Ansible install them: `ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags prereqs`
- **None of the above** if you only want to validate the repo — see
  "Validated without a cluster" below.

## Quick start (live run)

```bash
make cluster-up      # kind (3 nodes) + ingress-nginx
make deploy          # build echo-svc image, load into kind, apply good manifests
make observability   # kube-prometheus-stack + ServiceMonitor + alerts + dashboard
make smoke           # curl /, /health, /ready -> 200

# the fun part:
make break           # apply the broken variant, reproduce the stampede
kubectl -n echo get pods -w
make heal            # re-apply the good manifests, watch it recover

make cluster-down    # tear it all down
```

Step-by-step with what to watch and why:
[`docs/RUNBOOK.md`](docs/RUNBOOK.md).

## Repo layout

```
app/                FastAPI echo service (/health, /ready, /metrics), Dockerfile, tests
k8s/                GOOD manifests: deployment (requests/limits, probes), svc, pdb, hpa, ingress
k8s/incident/       BAD variant that reproduces the stampede (for the runnable diff)
terraform/          Local kind cluster + monitoring stack as code (EKS-portable)
ansible/            One playbook: install prereqs, bootstrap cluster + observability
ci/                 GitHub Actions workflow + Jenkinsfile (Jenkins-on-k8s, EFS-backed PVC)
observability/      kube-prometheus-stack values, ServiceMonitor, alert rules, Grafana dashboard
docs/               BROKE-FIXED-BUILT, INCIDENT-POSTMORTEM, ARCHITECTURE, PLAN, RUNBOOK
scripts/            helper bash (kind config, image load, smoke test, static validate)
Makefile            cluster-up / deploy / observability / break / heal / smoke / validate / cluster-down
```

## What it demonstrates (mapped to skills)

| Area | Where |
|---|---|
| Kubernetes/EKS reliability (requests/limits, probes, PDB, spread, HPA) | `k8s/` |
| Incident response & RCA | `docs/INCIDENT-POSTMORTEM.md`, `k8s/incident/` |
| Monitoring & alert design (Prometheus/Grafana/Datadog-style) | `observability/` |
| Terraform IaC | `terraform/` |
| Ansible config management | `ansible/` |
| CI/CD — GitHub Actions + Jenkins-on-k8s w/ EFS-backed storage | `ci/` |
| Security/GRC habits (non-root, PSA restricted, least privilege) | `app/Dockerfile`, `k8s/namespace.yaml`, `k8s/deployment.yaml` |

Full mapping + roadmap: [`docs/PLAN.md`](docs/PLAN.md).

## Validated without a cluster

Docker/kind weren't available when I authored this, so everything is built to
run live via the documented steps **and** statically validated with no cluster:

- **Every** `.yml`/`.yaml` is parsed with Python `yaml.safe_load_all` to confirm
  it loads (15/15 pass).
- Plain k8s manifests are schema-validated **offline** with `kubeconform -strict`
  against the upstream Kubernetes schemas (9/9 valid). I went with kubeconform
  over `kubectl --dry-run=client` deliberately: modern kubectl still reaches out
  to the API server for the API group list, so it isn't actually clusterless.
- CRD-based manifests (`ServiceMonitor`, `PrometheusRule`) are parse-validated
  only, since strict schema validation needs the prometheus-operator CRDs
  installed — noted as such.
- The app's own unit tests (`app/test_main.py`) pass — 5/5, covering the
  probe contract that caused the incident.
- Terraform is **validated by review** (provider pins, single-apply wiring), as
  `terraform` isn't installed here.
- The Dockerfile is reviewed for correctness; a live `docker build` is part of
  `make deploy` / CI.

Run it yourself:

```bash
make validate
```

## License

MIT — see [LICENSE](LICENSE).
