# Plan & strategy

## Why this repo exists

Recruiters and hiring managers skim certs. What actually lands is proof that you
**broke something, fixed something, and built something**, plus a writeup that
shows how you think under pressure. I have the real EKS incidents; this repo
makes them runnable and legible to someone who has five minutes.

So the strategy is simple: take my two real incidents, reproduce the failure
mode on a free local cluster, ship the correct fixes as code, and wrap it in the
CI/CD + observability that would have prevented it, then document it like an
actual SRE post-mortem.

## Goals

1. **Be runnable, not just readable.** `make break` reproduces the stampede;
   `make heal` recovers it. The lesson is executable.
2. **Be honest about local-vs-prod.** Everything targets local `kind` (no cost),
   but the prod deltas are spelled out so I'm never overselling.
3. **Map cleanly to my résumé** so an interviewer can connect a claim to a file.
4. **Validate without a cluster** so the repo is provably well-formed even on a
   machine with no Docker (see the "Validated without a cluster" note in the
   README).

## What it demonstrates → mapped to my skills

| Repo piece | Skill it proves |
|---|---|
| `k8s/deployment.yaml` requests/limits + probes | Kubernetes/EKS reliability engineering, root-cause fixes |
| `k8s/pdb.yaml`, topology spread, rollout strategy | Production-grade workload hardening |
| `k8s/incident/` + `docs/INCIDENT-POSTMORTEM.md` | Incident response, RCA, "how I think" |
| `observability/` (Prometheus, Grafana, alerts) | Datadog/Prometheus/CloudWatch monitoring, alert design |
| `terraform/` | Terraform IaC (pinned providers, modular, EKS-portable) |
| `ansible/bootstrap.yml` | Ansible config management / environment reproducibility |
| `.github/workflows/ci.yml` | GitHub Actions CI/CD, automated testing & validation |
| `ci/Jenkinsfile` + `ci/jenkins-pvc.yaml` | Jenkins-on-Kubernetes rebuild, EFS-backed persistence (incident #1) |
| `app/` (non-root, PSA-restricted, least-priv) | Security/GRC habits (CIS/NIST hardening) carried into DevOps |
| `Makefile`, `scripts/` | Bash automation, operable tooling |

## Non-goals

- Not a production service. It's a teaching artifact.
- Not multi-cloud or HA across regions; out of scope for a laptop demo.
- No secrets management theater; demo creds are clearly marked as demo-only.

## Roadmap

- [x] App + health/ready split + tests
- [x] Good vs bad manifests with a runnable diff
- [x] Observability: ServiceMonitor, dashboard, alert rules
- [x] Terraform (local kind) + Ansible bootstrap
- [x] GitHub Actions + Jenkinsfile (EFS-backed)
- [x] Post-mortem + broke/fixed/built + runbook
- [ ] Admission policy (Kyverno/OPA) to reject pods with no resource requests
- [ ] k6/locust load script to trigger the HPA and the stampede on demand
- [ ] EKS overlay (terraform EKS module + ECR + ALB) as a parallel path
- [ ] Chaos step (kill a node) wired into the runbook to show PDB + spread in action
