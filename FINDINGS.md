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

## Crunchy PGO v6.0.3 vs Percona 3.1.0

Both run Patroni with the Kubernetes API as DCS and behaved the same under faults.

| Scenario | Crunchy 6.0.3 | Percona 3.1.0 |
|---|---|---|
| Operator ready / 3-instance cluster ready | 27 s / 147 s | 36 s / 240 s |
| Primary pod deleted (direct / pgBouncer) | 2.4 / 15.7 s | 2.4 / 13.1 s |
| Planned switchover | 2.6 s | 2.4 s |
| Primary deleted, operator down | 2.5 s (fails over) | 3.4 s (fails over) |
| Pod partition with persistent clients: old primary stops / new promoted / overlap / lost | +13.8 / +27.0 / none / 394 | +13.6 / +26.9 / none / 391 |

**Generated configuration is identical.** That covers PostgreSQL defaults, pgBouncer, internal roles, Service and Secret names and keys, and the pgBackRest stanza.

**Differences:**
- The primary label is `role=master` on Crunchy and `role=primary` on Percona.
- Only the Crunchy image ships `pg_partman`, `pg_jobmon`, `timescaledb`, `orafce`, `plpython3u` (plus 3 transforms), `hypopg`, `passwordpolicy`, `pg_parquet` and `pgnodemx`.
- Only the Percona image ships `pg_repack`, `pg_stat_monitor` and `pg_tde`.
- v6 writes logs to `/pgdata/logs/postgres`.

## Crunchy → Percona migration (source: Crunchy 6.0.3, 332 MB, pg_partman, plpython3u, pg_stat_statements, set_user, 2 pg_cron jobs)

| Method (Percona docs, written for 5.8.x) | Result | Traps found |
|---|---|---|
| Backup and restore from Crunchy S3 repo | Ready in 50 s; all data | Crunchy S3 repo was `repo2`, so it must be mapped to dataSource `repo1`; `pg_stat_statements` and `set_user` **dropped in all DBs** (disabled built-ins are dropped); pg_cron not preloaded, and when enabled `cron.database_name` is forced to `postgres`, so jobs in the app DB never run; plpython3u function fails; `autoCreateUserSchema` default sends new tables to a per-user schema |
| Standby cluster + promote | Streaming in 55 s; **13 s** write downtime; zero loss | **Password rotated** at promotion unless the Secret is pre-copied; Crunchy-issued certificate kept (Crunchy hostnames, not renewed); with the shared repo, post-cutover Percona writes **do** come back to Crunchy on rollback (the guide says they don't); when we skipped the guide's demote-Percona step, both clusters archived into one repo on diverging timelines with no error |
| Reuse data volume | ~45 s once working; all data | PVC `selector` deadlocks on `WaitForFirstConsumer` storage (pod scheduled away from the PV, provisioner rejects the selector): hung 10 min until the instance was pinned to the PV's node; Crunchy deleted without a clean-shutdown step |

## Crunchy v6 features Percona 3.1 lacks

- `v1` API manifests: a translation is needed, and the docs cover v5.8 only.
- pgMonitor exporter and its dashboards stack.
- OpenTelemetry.
- A PGAdmin controller (the CRD exists without one).
- Auto-grow on by default, with thresholds.
- PostGIS 3.6.
- The extensions listed above.
- `volumes.temp`, Patroni logging, and Service traffic/IP-family policies.

## Cross-site DR switchover (two namespaces as two sites, shared S3, 1 instance per site)

Three writer clients per site log every acknowledged commit. Write downtime runs from the last ack on the old primary to the first ack on the new one; it excludes repointing applications.

| Run | Write downtime | Acked writes lost | Old primary afterwards |
|---|---|---|---|
| CNPG 1.30.1, archive-only, documented demote → `demotionToken` → promote with `promotionToken` | 8.5 s | 0 of 808 | Same pod and PVC; replica of new primary; caught up when the next WAL segment was archived (archive_timeout 5 min) |
| CNPG, no token, but the stale `promotionToken` left in the old primary's spec made its demotion **fail at admission**; promotion of the other side succeeded | — (both primaries ~170 s) | **5,604 of 5,604** acked on the old primary missing on the new | Diverged: "requested timeline 3 is not a child of this server's history"; PostgreSQL down while the Cluster reported "healthy"; rebuilt site B |
| CNPG, no token, proper demotion (race won) | 6.4 s | 0 of 803 | Rejoined automatically |
| Percona 3.1.0, repo-only standby, manual demote → wait for stable replay LSN → promote | 24.7 s (manual waits) | 0 of 819 | **Diverged** (shutdown checkpoint in unarchived segment: 0/70000A0 vs 0/7000000 received); no automatic rewind without a streaming source; rebuild needed |
| Percona, streaming + repo standby, same careful procedure | 24.2 s | 0 of 853 | Same pod and PVC; streaming from new primary immediately |
| Percona, streaming + repo, demote and promote immediately (no wait) | 1.9 s | 0 of 946 | Diverged slightly; **Patroni ran pg_rewind automatically**; streaming within seconds |

Neither operator blocks a second primary across clusters. CNPG's token handshake (`.partial` WAL archived on demotion plus a promotion that waits for that LSN) is the safe path for **archive-only** DR. Percona has no equivalent there and no documented role-reversal procedure. With streaming between sites, Percona's switchover worked without a rebuild and self-healed through pg_rewind.

Side finding: after deleting and recreating a PerconaPGCluster with the same name, a leftover `PerconaPGBackup` (no owner reference) made the new cluster report `replicaCreateBackupComplete: true` without taking a backup. The repo was empty, and the standby failed with "no backup set found to restore".
