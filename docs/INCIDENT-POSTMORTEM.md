# Post-mortem: pod-scheduling stampede → cascading EKS node failures

> This is a sanitized, generalized writeup of a real incident I worked, rebuilt
> here as a runnable demo. Names, exact numbers, and timestamps are
> reconstructed from memory, but the failure mode, the diagnosis path, and the
> fix are exactly what happened. The manifests in this repo (`k8s/` vs
> `k8s/incident/`) are the real before/after, shrunk to fit a laptop.

**Author:** Matthew
**Severity:** SEV-1 (partial outage of the service tier)
**Status:** Resolved, prevention shipped (this repo is part of the prevention)

---

## TL;DR

A deploy went out with **no resource requests or limits** on the pods. The
scheduler, seeing pods that "cost nothing," packed far too many onto a couple of
nodes. Under real traffic those pods all reached for memory at the same time. This was a
**scheduling stampede**: the nodes hit `MemoryPressure`, the kubelet started
**evicting**, evicted pods rescheduled onto the next node and pushed *it* over,
and the pressure rolled across the cluster. On top of that, our **liveness probe
was doing readiness's job** with a 1s timeout, so the kubelet also started
**killing healthy-but-slow pods**, producing a `CrashLoopBackOff` storm that
made the stampede worse. We had no alert on restart storms or OOMKills, so we
found out from the cascading node-`NotReady` pages after the blast radius had
already spread.

**Root cause:** missing resource requests/limits + a liveness probe pointed at a
heavy endpoint with brutal thresholds. **Fix:** right-sized requests/limits,
re-pointed and loosened the probes, added a PodDisruptionBudget, and rebuilt the
CI/CD path on Kubernetes with EFS-backed persistent storage so deploys are
reproducible and the pipeline isn't a SPOF.

---

## Timeline (approximate, the day of)

| Time (local) | What happened |
|---|---|
| 14:02 | Routine deploy of the service tier goes out. Manifests had no `resources` block (inherited from an older template nobody had revisited). |
| 14:09 | Traffic ramps into the afternoon peak. Pods on nodes `ip-...-41` and `ip-...-67` start climbing in memory. |
| 14:11 | First `OOMKilled` events. Pods restart, reschedule, land on the same hot nodes (no topology spread). |
| 14:13 | Node `...-41` reports `MemoryPressure=True`. kubelet begins evicting pods to reclaim memory. |
| 14:14 | Evicted pods reschedule onto `...-67` and a third node; **the pressure follows the pods**. Liveness probes (pointed at a heavy `/ready`-style endpoint, 1s timeout, threshold 1) start timing out under load → kubelet **kills** pods that were actually alive. |
| 14:16 | `CrashLoopBackOff` across most replicas. Two nodes go `NotReady`. **First page fires**, on node `NotReady`, not on the actual root cause. |
| 14:19 | I `kubectl describe nodes` + pull events: wall of `OOMKilled`, `Evicted`, `FailedScheduling: insufficient memory`. Realize there are no requests on any pod. |
| 14:24 | Cordon the flapping nodes, scale the deployment down to stop the reschedule churn, confirm in Datadog/Prometheus that memory working-set per pod is ~3x what the (nonexistent) request implied. |
| 14:31 | Roll out a hotfix manifest **with** right-sized requests/limits and corrected probes. Scheduler stops overpacking immediately. |
| 14:38 | Uncordon nodes, scale back up. Pods spread, memory steady, no more evictions. Service recovers. |
| 15:10 | Declared resolved. Started this writeup the same evening. |

**Blast radius:** elevated error rate / partial unavailability of the service
tier for ~25 minutes; 2 nodes briefly `NotReady`; no data loss (stateless
service).

---

## Root cause analysis

### Primary cause: no resource requests
With no `requests`, the scheduler's view of a pod's cost is ~zero, so it will
bin-pack aggressively. That's fine until the pods actually use memory. When peak
traffic hit, every over-packed pod grabbed real memory at once. The node's
allocatable memory was blown through, the kubelet's eviction thresholds tripped,
and eviction kicked in. **Eviction reschedules the pod**, and with no requests
the scheduler happily places it on the next node, so the failure is *mobile*.
That mobility is what turned one hot node into a cascade.

### Amplifier: liveness probe doing readiness's job
The liveness probe hit a heavy endpoint (effectively a readiness check) with
`timeoutSeconds: 1` and `failureThreshold: 1`. Under memory pressure the app got
slow, the probe timed out, and the kubelet **restarted alive pods**. Liveness is
supposed to mean "this process is wedged, restart it." Ours meant "this process
is busy." Restarting busy pods under load is how you manufacture a
`CrashLoopBackOff` storm.

### Contributing: no PDB, no topology spread, no alerts
- No **PodDisruptionBudget**: an automated node rollout drained on top of the
  evictions, briefly taking ready replicas to zero.
- No **topology spread**: replicas concentrated on two nodes, so the first hot
  node already held most of the service.
- No **alerts** on restart storms / OOMKills / node memory pressure, so the only
  signal was the downstream node-`NotReady` page, too late and pointing at the
  wrong layer.

---

## How I diagnosed it

The exact commands and signals, because "how you think" is the point:

```bash
# Nodes: who's under pressure and why
kubectl describe nodes | less        # MemoryPressure=True, eviction events
kubectl top nodes                    # working set vs allocatable

# Events: the smoking gun
kubectl get events -A --sort-by=.lastTimestamp | grep -Ei 'oom|evict|failedsched'
#   -> OOMKilled, Evicted, FailedScheduling: 0/3 nodes ... insufficient memory

# Pods: the crashloop and WHY they died
kubectl get pods -A -o wide          # see them piled on 2 nodes
kubectl describe pod <pod>           # Last State: Terminated, Reason: OOMKilled
kubectl get deploy <svc> -o yaml | grep -A3 resources   # <- empty. there it is.
```

In Datadog/Prometheus the picture matched: `container_memory_working_set_bytes`
per pod sat ~3x the (absent) request, `kube_pod_container_status_restarts_total`
was a vertical line, and `kube_node_status_condition{condition="MemoryPressure"}`
flipped to 1 right before the node went `NotReady`. Those three metrics are now
the basis of the alert rules in `observability/prometheus-rules.yaml`.

---

## The fix

All of this is in the repo as runnable manifests. The clean diff is
`diff -u k8s/deployment.yaml k8s/incident/deployment-bad.yaml`.

1. **Right-sized requests + limits** (`k8s/deployment.yaml`). Requests set from
   measured p95 working set (~80-96Mi mem, ~50m CPU); limits ~2x for burst
   headroom. The scheduler now reserves real memory and refuses to overpack, and
   this alone stops the cascade.
2. **Re-pointed + loosened probes.** Liveness → cheap `/health` only, with a 30s
   initial delay and `failureThreshold: 3`, plus a `startupProbe` so cold starts
   never race liveness. Readiness → `/ready`, which is *allowed* to fail and just
   pulls the pod from rotation instead of killing it.
3. **PodDisruptionBudget** (`k8s/pdb.yaml`, `minAvailable: 2`) so voluntary
   disruptions (drains, upgrades) can't take us below a safe floor; paired with
   `maxUnavailable: 0` on the rollout.
4. **Topology spread** across hostnames so replicas don't concentrate.
5. **CI/CD rebuilt on Kubernetes with EFS-backed storage** (incident #1, see
   below) so deploys are reproducible and the pipeline isn't a single-disk SPOF.
6. **Alerts** on restart storms, OOMKills, readiness 503s, node memory pressure,
   and replica floor: the signals that would have paged us at 14:11 instead of
   14:16.

---

## Incident #1 reference: the CI/CD gap and the Jenkins-on-k8s rebuild

The reason the bad template lingered long enough to bite us was partly a CI/CD
gap. Our Jenkins ran on a single VM, and when that box's workspace volume filled
up mid-incident-season, builds wedged and the pipeline went down, so manifest
changes were going out through inconsistent, partly-manual paths.

I rebuilt Jenkins to run **on Kubernetes** (ephemeral agent pods via the
Kubernetes plugin) with **EFS-backed persistent storage** for Jenkins home and a
shared build cache (`ReadWriteMany`, survives any node dying). No single node's
disk is a SPOF anymore, builds are stateless, and every deploy goes through the
same validated path. That pipeline is modeled in `ci/Jenkinsfile` +
`ci/jenkins-pvc.yaml` (EFS in prod, local-path in this kind demo; the only line
that changes is the StorageClass).

---

## Prevention / action items

- [x] Resource requests + limits required on every workload (enforced in review;
      `make validate` checks the manifest shape).
- [x] Probe standard: liveness = cheap health only; readiness = real check;
      startupProbe for slow starts.
- [x] PodDisruptionBudget on every user-facing Deployment.
- [x] Alert rules for restart storms / OOMKills / memory pressure / replica floor
      (`observability/prometheus-rules.yaml`).
- [x] This repo: a reproducible "break it / heal it" demo so the lesson is
      runnable, not just written down (`make break`, `make heal`).
- [ ] (Org follow-up) Admission policy to reject pods with no resource requests.

## What I'd do differently

Alert on the *cause* layer, not just the symptom layer. We had node-`NotReady`
paging but nothing on the restart/OOM/pressure metrics that precede it by
minutes. Leading indicators buy you the time to act before a hot node becomes a
cascade.
