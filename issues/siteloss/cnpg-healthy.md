### Is there an existing issue already for this bug?

Related but closed as stale: #7895 ("Cluster in healthy state" despite replica errors). This report covers the **designated primary of a replica cluster** being unable to start.

### Version

1.30.1 (barman-cloud plugin 0.15.1)

### What version of Kubernetes are you using?

1.35 (k3s v1.35.9+k3s1)

### What is your Kubernetes environment?

Self-managed: k3s on Linode VMs (2 vCPU / 4 GB), local-path storage

### How did you install the operator?

YAML manifest (`cnpg-1.30.1.yaml`), plugin from its release manifest

### What happened?

In a distributed topology (two Cluster resources, `replica.self` / `replica.primary` / `replica.source`, barman-cloud plugin), after a demotion the former primary's designated primary could not start, yet the Cluster reported **`Cluster in healthy state`** and condition `Ready=True` for as long as we watched (10+ minutes). We saw this three times:

1. Planned switch where demotion was blocked by a leftover `promotionToken` (see the separate issue on that), and the other side was promoted anyway.
2. Unplanned site loss, streaming + object store: site A powered off, site B promoted with `replica.primary: dr-b` (no token is available when site A is gone). Site A powered back on, then patched to `replica.primary: dr-b`.
3. The same with object store only.

In each case `dr-a-1` (designated primary) crash-looped:

```
FATAL: requested timeline 2 is not a child of this server's history
LOG:  startup process (PID 231) exited with exit code 1
LOG:  database system is shut down
"msg":"PostgreSQL process exited with errors","logger":"instance-manager"
```

Meanwhile:

```
$ kubectl -n site-a get cluster dr-a
NAME   AGE   INSTANCES   READY   STATUS                     PRIMARY
dr-a   56m   2           1       Cluster in healthy state   dr-a-1
```

`status.conditions` had `Ready=True` ("Cluster is Ready") and `ContinuousArchiving=True`. The second instance was in recovery but had no WAL receiver.

### Expected

A designated primary whose PostgreSQL cannot start should not be reported healthy/Ready. A condition (e.g. `DesignatedPrimaryNotRunning` / `TimelineDiverged`) and an Event pointing to the timeline mismatch would make this diagnosable; today the only signal is in the pod log.

### Reproduction

Scripts, manifests and raw logs: https://github.com/Percona-Lab/pgk8s-eval (`dr/`, `siteloss/`, `results/siteloss/`). This was found during a comparison of PostgreSQL operators; one run per scenario.

### Code of Conduct

- [x] I agree to follow this project's Code of Conduct
