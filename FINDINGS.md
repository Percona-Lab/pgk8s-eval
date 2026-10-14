# Findings

All results are from single runs on the lab described in the [README](README.md). Times are seconds after the fault was injected. **Write outage** means the time from the last successful write before the event to the first successful write after it, measured by a probe that opens a new connection and runs an `INSERT` every ~200 ms.

## Failover (write outage, seconds)

| Scenario | Percona direct | Percona via pgBouncer | CloudNativePG `-rw` |
|---|---|---|---|
| Primary pod deleted | 2.4 | 13.1 | 7.1 |
| Postmaster `kill -9` | 10.8 | 20.1 | 5.3 |
| Planned switchover (documented procedure) | 2.4 | 15.6 | 11.4 |
| Primary deleted while operator scaled to 0 | 3.4 | 17.6 | 101.5 (no failover until operator returned) |
| Node hard power-off (auto-rebooted) | 26.9 | 47.2 | 74.0 |
| Full node network partition (240 s) | 31.4 | 45.7 | 97.5 |
| Kubelet loses API server, pod network intact | 0 | 0 | 135.8 (primary healthy, dropped from `-rw`) |
| Node lost for 10 min, backup pod on the same node | 271.3 (promotion stalled on pgBackRest `restore_command`) | 271.4 | 401.4 (reconcile blocked by Barman plugin until eviction) |
| Rolling image update | 3.4 | ~18 | 13.6 |

- **pgBouncer adds 10–15 s to every Percona failover** (`server_login_retry` = 15 s). Clients see a misleading `FATAL: SSL required`.
- **CloudNativePG cannot fail over without its operator.** Patroni does not need the Percona operator.

## Split-brain (pod-level partition, clients keep persistent connections)

The method follows [Coroot's reproduction](https://coroot.com/blog/reproducing-split-brain-on-cloudnativepg/). The primary pod is cut off from its replicas, the operator(s) and the API server for 300 s, while three writers keep their sessions. Every acknowledged write is checked against the final table.

| Run | Old primary's last ack | New primary promoted | Dual-primary overlap | Acknowledged writes lost |
|---|---|---|---|---|
| CloudNativePG 1.30.1 defaults | +206.7 | +77.4 | **129.3 s** | 5,905 (3,680 during overlap) |
| CloudNativePG `smartShutdownTimeout: 0` | +23.3 | +73.8 | none | 660 |
| CloudNativePG `smartShutdownTimeout: 0`, `failoverDelay: 30` | +25.7 | +107.6 | none | 740 |
| CloudNativePG quorum sync (`dataDurability: required`) | blocked | +76.4 | none | 0 (clients stuck until +207) |
| Percona 3.1.0, direct | +13.6 | +26.9 | none | 391 |
| Percona 3.1.0, via pgBouncer | +19.2 | +32.5 | none | 368 |

**Other scenarios:**

| Scenario | CloudNativePG 1.30.1 | Percona 3.1.0 |
|---|---|---|
| Node loses control plane; primary loses API and 5432 to replicas, port 8000 open | No failover, no split, no loss; new connections failed 264 s | Demoted +10.5, promoted +21.8, 305 lost |
| 30 s freeze of primary pod + kubelet | No failover, no loss | not run |
| 120 s freeze of primary pod + kubelet | Promoted +67; after thaw old primary committed 409 writes in ~1 s (lost) | Promoted +27; after thaw 53 writes in 0.3 s (lost) |

- The CloudNativePG split-brain is [#11280](https://github.com/cloudnative-pg/cloudnative-pg/issues/11280). It is still open in 1.30.1, and the code fix is planned for 1.31. Until then, use `smartShutdownTimeout: 0` or quorum sync.
- "Lost" counts for runs without overlap are ordinary async-replication loss: writes acknowledged by the isolated primary before it was fenced.

## Backup and restore (337 MB database)

| Test | Percona | CloudNativePG |
|---|---|---|
| Full backup to S3, defaults | 323 s | 299 s |
| Full backup, immediate checkpoint | 43 s | 19 s |
| In-place PITR | 33 s (26 s write downtime) | not supported |
| PITR to new cluster | 43 s (1 instance) | primary 61 s, 3 instances 126 s |

Both default backups wait for a spread checkpoint (~5 min).

## Install

| | Percona | CloudNativePG |
|---|---|---|
| Operator ready | 36 s | 14 s |
| Sample cluster ready | 240 s | 112 s |
| Backups out of the box | yes (PVC repo, first full backup automatic) | no (needs cert-manager + plugin + object store) |
