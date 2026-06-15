# k8s/incident/ — the broken variant

This directory holds the deliberately-broken Deployment that reproduces the
pod-scheduling stampede described in [`../../docs/INCIDENT-POSTMORTEM.md`](../../docs/INCIDENT-POSTMORTEM.md).

It exists so the post-mortem can reference an **exact, runnable diff** instead
of hand-waving about "we didn't have resource requests."

## See the diff

```bash
diff -u k8s/deployment.yaml k8s/incident/deployment-bad.yaml
```

## What's wrong, on purpose

| Problem in `deployment-bad.yaml` | Why it hurts | Fix in `../deployment.yaml` |
|---|---|---|
| No `resources.requests` / `limits` | Scheduler overpacks the node → memory-pressure evictions cascade | Right-sized requests + 2x limits |
| `replicas: 10` with no requests | Stampede on schedule | `replicas: 3` + HPA that can actually measure utilization |
| Liveness probe hits `/ready`, `timeout 1s`, `failureThreshold 1` | Slow-but-alive pods get **killed** → CrashLoopBackOff storm | Liveness hits cheap `/health`, generous thresholds + startupProbe |
| No readiness probe | Traffic hits un-warmed pods → user 503s | Tuned readiness on `/ready` |
| No PodDisruptionBudget | A node drain can take us to zero | `pdb.yaml` with `minAvailable: 2` |
| `maxUnavailable: 50%` | Rollout itself drops capacity | `maxUnavailable: 0`, `maxSurge: 1` |
| No topology spread | Pods concentrate on hot nodes | `topologySpreadConstraints` across hostnames |

Run `make break` to apply this, watch it misbehave, then `make heal` to restore
the good manifests.
