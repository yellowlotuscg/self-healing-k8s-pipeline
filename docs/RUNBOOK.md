# Runbook

Exact commands to bring the demo up, deploy, **break it on purpose**, watch it
self-heal, and tear it down. Run from the repo root.

## 0. Prerequisites

You need Docker running, plus `kind`, `kubectl`, and `helm`. Either install them
yourself or let Ansible do it:

```bash
ansible-playbook -i ansible/inventory.ini ansible/bootstrap.yml --tags prereqs
```

> No Docker / no cluster? You can still validate everything statically:
> ```bash
> make validate
> ```

## 1. Bring the cluster up

```bash
make cluster-up      # kind (3 nodes) + ingress-nginx
```

Verify:

```bash
kubectl get nodes                 # 1 control-plane + 2 workers, all Ready
kubectl -n ingress-nginx get pods # controller Running
```

## 2. Deploy the app (the GOOD manifests)

```bash
make deploy          # builds echo-svc:local, loads into kind, applies k8s/
```

Verify:

```bash
kubectl -n echo get pods,svc,pdb,hpa
kubectl -n echo rollout status deploy/echo-svc
make smoke           # port-forwards and curls /, /health, /ready -> all 200
```

## 3. Observability (optional but recommended)

```bash
make observability   # kube-prometheus-stack + ServiceMonitor + alerts + dashboard
```

Open Grafana (creds admin/admin — demo only):

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# browse http://localhost:3000 -> dashboard "echo-svc / self-healing demo"
```

Check the alert rules loaded:

```bash
kubectl -n echo get prometheusrule echo-svc-reliability
```

## 4. Break it on purpose (reproduce the stampede)

```bash
make break           # applies k8s/incident/deployment-bad.yaml
kubectl -n echo get pods -w
```

What you'll see and **why** (cross-ref the [post-mortem](INCIDENT-POSTMORTEM.md)):

- Replicas jump to 10 with **no resource requests** → scheduler overpacks nodes.
- The liveness probe points at `/ready` with a 1s timeout / threshold 1 → as
  pods get busy they get **killed**, not just pulled from rotation →
  `CrashLoopBackOff`.
- No readiness probe → traffic hits un-warmed pods → 503s.

Watch the signals:

```bash
kubectl -n echo get events --sort-by=.lastTimestamp | grep -Ei 'oom|evict|backoff|kill'
kubectl top pods -n echo            # memory climbing, no limits to cap it
kubectl describe nodes | grep -i pressure
```

In Grafana the "Pod restarts (10m)" and "OOMKills" panels light up, and the
`EchoPodRestartStorm` / `EchoOOMKilled` alerts move to Pending/Firing — i.e. the
alerts that *would have caught this in prod*.

## 5. Watch it self-heal

```bash
make heal            # re-applies the GOOD deployment
kubectl -n echo rollout status deploy/echo-svc --timeout=120s
kubectl -n echo get pods -w         # back to 3 healthy, spread across nodes
make smoke                          # green again
```

The fix takes effect immediately: with real requests the scheduler stops
overpacking, the corrected liveness probe stops killing busy pods, and the PDB
keeps ≥2 ready throughout.

### Bonus: readiness self-heal without killing anything

Force a pod to report not-ready and watch the Service pull it from rotation
while it stays *up* (the behavior the incident's probes got wrong):

```bash
kubectl -n echo set env deploy/echo-svc FAIL_READY=1
kubectl -n echo get endpoints echo-svc -w   # endpoints shrink, pods stay Running
kubectl -n echo set env deploy/echo-svc FAIL_READY=0   # endpoints come back
```

### Bonus: prove the PDB

```bash
kubectl drain <a-worker-node> --ignore-daemonsets --delete-emptydir-data
# the drain blocks rather than dropping echo-svc below minAvailable: 2
kubectl uncordon <a-worker-node>
```

## 6. Tear down

```bash
make cluster-down    # deletes the kind cluster (takes everything with it)
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pods `ImagePullBackOff` | image not loaded into kind | `make build-load` (or `scripts/load-image.sh`) |
| Ingress 404 / connection refused | controller not ready, or host not mapped | `kubectl -n ingress-nginx get pods`; add `127.0.0.1 echo.local` to /etc/hosts |
| Grafana dashboard missing | sidecar didn't pick up the ConfigMap | re-run `bash scripts/grafana-dashboard-configmap.sh`; check label `grafana_dashboard=1` |
| `make deploy` can't find image | Docker not running | start Docker, re-run |
