# pgk8s-eval: Percona Operator for PostgreSQL vs CloudNativePG and Crunchy PGO

Hands-on evaluation of PostgreSQL operators for Kubernetes on identical hardware. It also covers migration from Crunchy PGO v6 to Percona. Both were installed from their own documentation and then put through failover, split-brain, backup/PITR and troubleshooting scenarios.

| Operator | Version | HA | Backup |
|---|---|---|---|
| [Percona Operator for PostgreSQL](https://github.com/percona/percona-postgresql-operator) | 3.1.0 | Patroni 4.1.5, Kubernetes API as DCS | pgBackRest 2.59 |
| [CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg) | 1.30.1 | Instance manager + operator, primary Lease | Barman Cloud plugin 0.15.1 |
| [Crunchy Postgres for Kubernetes (PGO)](https://github.com/CrunchyData/postgres-operator) | 6.0.3 | Patroni (same design as Percona) | pgBackRest 2.59 |

Tests ran on 13–14 October 2026. A summary of results is in [FINDINGS.md](FINDINGS.md). Every number in it can be traced to a log in [`results/`](results/).

## Lab

- **Nodes:** 4 × Linode g6-standard-2 (2 vCPU, 4 GB RAM), Ubuntu 24.04, region us-southeast.
- **Kubernetes:** k3s v1.35.9+k3s1, with 1 control-plane node (tainted `NoSchedule`) and 3 workers. Storage is local-path; the network is flannel VXLAN.
- **Object storage:** an S3-compatible endpoint with TLS on the control-plane node ([SeaweedFS](lab/manifests/s3-seaweedfs.yaml)). MinIO no longer publishes container images, so SeaweedFS stands in; pgBackRest requires HTTPS for S3.
- **Clusters:**
    - Percona: `deploy/cr.yaml` unchanged, giving 3 PostgreSQL 18.6 instances, 3 pgBouncer and a pgBackRest repo-host.
    - CloudNativePG: `cluster-example.yaml` (3 instances, PG 18.6) plus the Barman Cloud plugin.
- **Data:** pgbench scale 20 (337 MB) in both clusters.

## Repository layout

| Path | Contents |
|---|---|
| [`lab/`](lab/) | Linode provisioning (`mk.py`, `fw.py`, `linode.py`, reads `LINODE_TOKEN`), hostname reset, helper functions (`h.sh`), and the manifests used: S3 endpoint, backup/restore/PITR CRs, S3 repo patch, clone-to-new-cluster, fault-injection clusters |
| [`failover/`](failover/) | Write probe (`probe.sh`), outage analyzer (`analyze.py`), scenario runner (`run.sh`) and the scenario scripts in [`failover/scenarios/`](failover/scenarios/) (`p_*` = Percona, `c_*` = CloudNativePG) |
| [`splitbrain/`](splitbrain/) | Split-brain harness: persistent-connection writers (`writer.sh`, `writers.yaml.tpl`), pod-level partition (`isolate.sh`), control-plane-only "blind spot" fault (`blindspot.sh`), VM-pause approximation (`freeze.sh`), cleanup, runners (`run.sh`, `run_fault.sh`, `chain*.sh`) and the ledger analyzer (`analyze_sb.py`) |
| [`results/`](results/) | Raw logs and per-run analyses (see the index below) |
| [`notes/`](notes/) | Documentation review (`docs_review.md`), split-brain research (`isolated_primary_research.md`), Crunchy status, CRD mapping and migration research (`crunchy_research.md`), and a snapshot of Percona's Crunchy migration guides as tested (`percona-migration-docs/`) |
| [`issues/`](issues/) | Bodies of the GitHub issues and comments filed from this work |
| [`crunchy/`](crunchy/) | Crunchy PGO v6.0.3 install kustomization, the `hippo` source cluster, Percona migration targets (`mig-restore`, `mig-standby`, `mig-volume`), failover scenarios (`k_*`) and migration scripts (`m2_cutover.sh`, `m3_volume.sh`) |
| [`dr/`](dr/) | Cross-site DR switchover tests: two-site CNPG replica clusters (distributed topology) and Percona standby clusters (repo-only and streaming), runner, analyzer, scenarios |
| [`siteloss/`](siteloss/) | Unplanned site-loss tests across two separate k3s clusters in different regions (object storage and clients at a third site): manifests per site, `setup.sh`, `sitelost.sh` (power off site A, promote B, power A back on, rejoin), `rebuild_a.sh`, `analyze.py`. Results in `results/siteloss/` |
| [`reports/`](reports/) | Standalone HTML reports: the full comparison, and product/docs recommendations for Percona. Download and open them locally |

## Reproducing

1. **Provision.** Run `python3 lab/mk.py` and `python3 lab/fw.py` (needs `LINODE_TOKEN`). Then run `lab/reset.sh <hostname>` on each node, because Linode images ship with hostname `localhost` and k3s nodes would collide.
2. **Install k3s.**
    - Server: `--node-ip <private-ip> --node-taint node-role.kubernetes.io/control-plane=true:NoSchedule`.
    - Agents: `K3S_URL=https://<server-private-ip>:6443`.
    - Note that flannel uses the nodes' **public** IPs for VXLAN when `--flannel-iface eth0` is set. Partition scripts must account for this.
3. **Install the operators exactly as documented.**
    - Percona: `kubectl apply --server-side -f https://raw.githubusercontent.com/percona/percona-postgresql-operator/v3.1.0/deploy/bundle.yaml -n postgres-operator`, then `deploy/cr.yaml`.
    - CloudNativePG: `kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml`, then `cluster-example.yaml`, then cert-manager and `plugin-barman-cloud` v0.15.1.
4. **Deploy the S3 endpoint and backups.** Apply `lab/manifests/s3-seaweedfs.yaml` (set your own credentials and TLS secret), `pct-patch.yaml` (Percona repo2 S3) and `cnpg-store.yaml` (CloudNativePG `ObjectStore`).
5. **Run failover scenarios.** Start the three probe pods (see `failover/probe.sh`; they run on the control-plane node). Then run, for example, `failover/run.sh t1_cnpg_poddelete cnpg failover/scenarios/c_poddel.sh`.
6. **Run split-brain scenarios.** Copy `splitbrain/{isolate,blindspot,freeze,cleanup}.sh` to the workers. Then run, for example, `splitbrain/run.sh <name> cnpg <node> <primary-pod> postgres <node-pod-cidr> "<operator/plugin IPs>" 300 c`.
    - The partition is applied with iptables **inside the primary pod's network namespace**. It is entered through the pod sandbox PID, so container restarts don't strand the rules.
    - Client pods on the control-plane node keep their connections.
    - `analyze_sb.py` checks every acknowledged `(id, client, commit ts)` against the final table.

Scripts assume the host names `pk-cp`, `pk-w1..3` in an SSH config, plus the namespaces and cluster names above. Public IPs are replaced with `<node-public-ip>`. Credentials are not included.

## Results index

| Test | Files |
|---|---|
| Install timings | `percona_install.log`, `cnpg_install.log`, `cnpg_plugin_install.log`, `footprint.log` |
| Primary pod delete / kill -9 / switchover / operator down | `t1_*`, `t2_*`, `t3_*`, `t4_*` + `probe-*.log`, `summary_t1_t5.txt` |
| Node power-off (auto-reboot) | `t5_node_w1.log` |
| Kubelet loses API server | `t6_apiloss_*` |
| Full node partition | `t7_*` (backup pods co-located), `t10_*` (CNPG), `t11_*` (Percona) |
| 10-min node loss with backup pods co-located | `t8_nodeloss_w3.log`, manual recovery `t9_manual_recovery.log` |
| Rolling image update | `t12_*` |
| Backups, PITR, clone | `backup1.log`, `backup2_fast.log`, `pitr_*.log`, `clone_percona.log` |
| Troubleshooting fault injection | `ts1_*`, `ts3_s3creds.log`, `observability.log` |
| Split-brain (pod partition, persistent clients) | `sb_cnpg-default`, `sb_cnpg-sst0`, `sb_cnpg-sst0-fd30`, `sb_cnpg-syncquorum`, `sb_pct-direct`, `sb_pct-bouncer` |
| Control-plane-only "blind spot" | `sb_cnpg-blindspot`, `sb_pct-blindspot` |
| VM-pause approximation | `sb_cnpg-freeze30`, `sb_cnpg-freeze120`, `sb_pct-freeze120` |
| Crunchy install, config/extension diff vs Percona, v6 features | `crunchy_install.log`, `crunchy_cluster.log`, `crunchy_vs_percona_config.txt`, `crunchy_vs_percona_sql.txt`, `crunchy_v6_features.txt` |
| Crunchy failover and split-brain | `k1_*`, `k3_*`, `k4_*`, `sb_crunchy-direct` |
| Crunchy → Percona migration: backup/restore | `mig_source_backup.log`, `mig1_restore_validation.txt`, `mig1_pgcron_enable.txt` |
| Crunchy → Percona migration: standby + cutover + rollback | `mig2_standby_setup.log`, `m2_standby_cutover.log`, `mig2_standby_validation.txt`, `mig2_rollback.log`, `mig2_shared_repo_after_rollback.txt` |
| Crunchy → Percona migration: volume reuse | `m3_volume_reuse.log` |

Each `sb_*` directory holds the writer ledgers (`c1..c3.log`), the final table (`final.txt`), cluster status every 10 s (`status.log`), and `analysis.txt`. In runs where no failover happened (`sb_cnpg-blindspot`, `sb_cnpg-freeze30`), the "old primary" simply stayed primary.

`sb_INVALID_hostns_partition` is kept for transparency. A script bug applied the partition to the whole node instead of the pod, so it is excluded from all findings.

## Crunchy PGO

Crunchy images come from the Crunchy Developer Portal and are subject to the [Crunchy Developer Program terms](https://www.crunchydata.com/developers/terms-of-use); they were used here for evaluation only.

The Crunchy operator was installed cluster-wide into namespace `pgo` with `kubectl apply --server-side -k` on a kustomization over `config/default` at tag v6.0.3. The cluster `hippo` ran in namespace `crunchy`, next to the Percona operator in `postgres-operator`.

The three migration methods followed [Percona's guides](https://docs.percona.com/percona-operator-for-postgresql/latest/migrate-from-crunchy.html), which are written for Crunchy 5.8.x, and then fixed where they failed. The volume-reuse test deletes the Crunchy cluster.

## Limitations

- Each scenario was run once on small VMs.
- Storage was local-path. Network-attached volumes would change node-loss recovery.
- The VM pause is approximated by freezing the pod cgroup and SIGSTOPping the k3s agent.
- PMM, major upgrades and pg_tde were assessed from the documentation only.
- Planned DR switchovers used two namespaces in one cluster. Unplanned site loss used two clusters in different Linode regions (us-southeast, us-east; ~20 ms) with S3 and clients in us-central; data was ~30 MB, so rebuild times are a lower bound.

## Issues filed

- percona-postgresql-operator: [#1848](https://github.com/percona/percona-postgresql-operator/issues/1848), [#1849](https://github.com/percona/percona-postgresql-operator/issues/1849), [#1850](https://github.com/percona/percona-postgresql-operator/issues/1850), [#1851](https://github.com/percona/percona-postgresql-operator/issues/1851), [#1852](https://github.com/percona/percona-postgresql-operator/issues/1852)
- k8spg-docs: [#450](https://github.com/percona/k8spg-docs/issues/450), [#451](https://github.com/percona/k8spg-docs/issues/451)
- cloudnative-pg: [#11655](https://github.com/cloudnative-pg/cloudnative-pg/issues/11655), [#11656](https://github.com/cloudnative-pg/cloudnative-pg/issues/11656), [#11657](https://github.com/cloudnative-pg/cloudnative-pg/issues/11657), [#11658](https://github.com/cloudnative-pg/cloudnative-pg/issues/11658), plus results posted on [#11280](https://github.com/cloudnative-pg/cloudnative-pg/issues/11280#issuecomment-6165732927)
- Crunchy → Percona migration: percona-postgresql-operator [#1859](https://github.com/percona/percona-postgresql-operator/issues/1859), [#1860](https://github.com/percona/percona-postgresql-operator/issues/1860), [#1861](https://github.com/percona/percona-postgresql-operator/issues/1861), [#1862](https://github.com/percona/percona-postgresql-operator/issues/1862), [#1863](https://github.com/percona/percona-postgresql-operator/issues/1863), [#1864](https://github.com/percona/percona-postgresql-operator/issues/1864), [#1865](https://github.com/percona/percona-postgresql-operator/issues/1865); k8spg-docs [#453](https://github.com/percona/k8spg-docs/issues/453), [#454](https://github.com/percona/k8spg-docs/issues/454), [#455](https://github.com/percona/k8spg-docs/issues/455), [#456](https://github.com/percona/k8spg-docs/issues/456), [#457](https://github.com/percona/k8spg-docs/issues/457)
- Cross-site DR: percona-postgresql-operator [#1867](https://github.com/percona/percona-postgresql-operator/issues/1867), [#1868](https://github.com/percona/percona-postgresql-operator/issues/1868), [#1869](https://github.com/percona/percona-postgresql-operator/issues/1869), [#1870](https://github.com/percona/percona-postgresql-operator/issues/1870); k8spg-docs [#458](https://github.com/percona/k8spg-docs/issues/458)

## License

Scripts and documentation are released under the Apache License 2.0.
