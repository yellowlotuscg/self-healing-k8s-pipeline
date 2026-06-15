# Broke / Fixed / Built

The 60-second version. If you only read one doc, read this one, then the
[post-mortem](INCIDENT-POSTMORTEM.md) for the full story.

## What I broke

A Kubernetes service tier (on EKS) went out with **no resource requests or
limits** and a **liveness probe pointed at a heavy endpoint with a 1-second
timeout**. Under peak traffic the scheduler had over-packed the nodes (pods that
"cost nothing" get bin-packed hard), every pod grabbed memory at once. This was a
**pod-scheduling stampede**: nodes hit `MemoryPressure`, the kubelet started
evicting, evicted pods rescheduled onto the next node and pushed it over too, and
the tight liveness probe simultaneously **killed healthy-but-slow pods** into a
`CrashLoopBackOff` storm. Two nodes went `NotReady`. ~25 min partial outage.

> Reproduce it yourself: `make break` (applies
> [`k8s/incident/deployment-bad.yaml`](../k8s/incident/deployment-bad.yaml)).

## What I fixed

- **Right-sized resource requests + limits** from measured usage → scheduler
  stops overpacking → cascade stops. This was the actual root-cause fix.
- **Re-pointed and loosened the probes:** liveness → cheap `/health` with a
  startupProbe so it never races startup or kills busy pods; readiness →
  `/ready`, which is *allowed* to fail and just pulls a pod from rotation.
- **PodDisruptionBudget** (`minAvailable: 2`) + `maxUnavailable: 0` rollout so a
  drain or deploy can't take us below a safe floor.
- **Topology spread** so replicas don't concentrate on hot nodes.
- **Rebuilt the CI/CD path on Kubernetes with EFS-backed persistent storage**
  (separate earlier incident: our single-VM Jenkins wedged when its disk filled).
  Ephemeral agent pods, shared `ReadWriteMany` cache, no single-disk SPOF.

> Recover from the break: `make heal`. See the exact diff:
> `diff -u k8s/deployment.yaml k8s/incident/deployment-bad.yaml`.

## What I built

A **self-healing Kubernetes CI/CD + observability demo** that runs free on a
local `kind` cluster but mirrors the real EKS incident end to end:

- **`app/`**: tiny FastAPI service with a proper `/health` vs `/ready` split
  (the distinction that bit us), Prometheus `/metrics`, non-root container.
- **`k8s/`**: the *fixed* manifests (right-sized resources, tuned probes, PDB,
  HPA, topology spread) **and** `k8s/incident/`, the *broken* variant, so the
  post-mortem points at a runnable diff.
- **`observability/`**: kube-prometheus-stack values, a ServiceMonitor, a
  Grafana dashboard, and the **alert rules that would have caught the stampede**
  (restart storms, OOMKills, readiness 503s, node memory pressure, replica floor).
- **`terraform/`**: local kind cluster + monitoring stack as code (swap the
  kind resource for the EKS module and it's the same shape).
- **`ansible/`**: one playbook to install prereqs and bootstrap the whole thing.
- **`ci/`**: GitHub Actions (lint/test/build/kind-smoke/manifest-validate) and a
  **Jenkinsfile** modeling the Jenkins-on-Kubernetes rebuild with the EFS-backed
  PVC.
- **`docs/`**: this file, the [post-mortem](INCIDENT-POSTMORTEM.md),
  [architecture](ARCHITECTURE.md), [plan](PLAN.md), and an operational
  [runbook](RUNBOOK.md) for breaking it and watching it self-heal.

The point: I broke something real, I fixed it with the boring correct controls,
and I built a thing you can run that proves I understand *why* each control
matters.
