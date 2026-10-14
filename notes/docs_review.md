# Percona Operator for PostgreSQL vs CloudNativePG: documentation-based review

*Prepared 2026-10-13. Desk research only (docs, GitHub API, release notes, source). Nothing was run on a cluster. Anything not confirmed from a primary source is marked **unverified**.*

Sources used:
- Percona docs: https://docs.percona.com/percona-operator-for-postgresql/latest/ (served version is 3.1.0). Docs source is `github.com/percona/k8spg-docs`, branch `3.0`, last commit 2026-10-06; its `variables.yml` has `release: 3.1.0`.
- Percona code: `github.com/percona/percona-postgresql-operator` (tag v3.1.0 and main).
- CNPG docs: https://cloudnative-pg.io/docs/1.30/ . The old `https://cloudnative-pg.io/documentation/current/...` URLs now meta-refresh to `/docs/devel/...`; see the docs-quality findings. Docs source is `cloudnative-pg/cloudnative-pg/docs/src` on main, as of 2026-10-13.
- Barman Cloud plugin docs: https://cloudnative-pg.io/plugin-barman-cloud/ (source `cloudnative-pg/plugin-barman-cloud/web/docs`).
- GitHub REST API (unauthenticated), queried 2026-10-13.

---

## 1. Current versions, cadence, support, governance

### 1.1 Latest releases

| | Percona Operator for PostgreSQL | CloudNativePG |
|---|---|---|
| Latest release | **v3.1.0, 2026-09-09** | **v1.30.1, 2026-09-23** (with v1.29.3 on the same day) |
| Previous minor | v3.0.0, 2026-05-22 | v1.30.0, 2026-06-29 |
| Next planned | unverified (no public roadmap date found) | 1.31.0 was planned for "~ Sep, 2026" on the supported-releases page. As of 2026-10-13 there is no 1.31 tag or RC, so it is **late**. |
| Helm chart | `percona/pg-operator` 3.1.0 and `percona/pg-db` 3.1.0 (2026-09-09); `pg-db-3.0.1` was released 2026-07-17 | `cnpg/cloudnative-pg` 0.29.1 (appVersion 1.30.1, 2026-09-23); `cnpg/cluster` 0.9.0 (2026-10-01); `cnpg/plugin-barman-cloud` 0.8.1 (2026-09-30) |
| Backup plugin | n/a (pgBackRest is built in) | plugin-barman-cloud **v0.15.1, 2026-09-30** |
| Image refresh note | Release notes for 3.1.0 say component images were rebuilt on 2026-10-05 for CVEs: PG 18.6.1-**3**, pgBouncer 1.25.2-**8**, pgBackRest 2.59.1-**2**. However, `deploy/cr.yaml` at tag v3.1.0 still pins `percona-distribution-postgresql:18.6.1-1`, `percona-pgbouncer:1.25.2-6` and `percona-pgbackrest:2.59.0-1`. **The quickstart therefore deploys older image builds than the docs recommend.** The tester should check which images actually run. | Default operand image in source (`pkg/versions/versions.go`): `ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie`; PgBouncer `ghcr.io/cloudnative-pg/pgbouncer:1.26.0` |

### 1.2 Release history, last ~18 months (GitHub releases API)

**Percona (minor/major and patch):**

| Version | Date | Highlights (from release notes) |
|---|---|---|
| 2.5.1 | 2025-03-03 | patch |
| 2.6.0 | 2025-03-17 | Backup improvements, PG 17 support, pgvector in image |
| 2.7.0 | 2025-07-18 | PMM3 support, Patroni config override, sleep-forever debug mode, concurrent reconcile workers |
| 2.8.0 | 2025-11-13 | Huge pages, custom user creds respected, S3 path-style for extensions, official PG Docker images |
| 2.8.1 | 2025-12-16 | patch |
| 2.8.2 | 2025-12-25 | patch |
| 2.9.0 | 2026-04-01 | PG 18 is the default; **major upgrades GA**; **PVC snapshot backups (tech preview)**; standby WAL-lag detection; LDAP; cert-manager automation; pprof; PG 13 removed; PMM2 deprecated; Red Hat Marketplace catalog dropped |
| 3.0.0 | 2026-05-22 | **Crunchy CRDs renamed to the `upstream.pgv2.percona.com` API group** with automatic migration (it can now coexist with Crunchy PGO); migration-from-Crunchy guides; OLM namespace-scoping fixes; official upgrade image |
| 3.1.0 | 2026-09-09 | **pg_tde TDE (PG 17/18, Vault KV v2 only)**; persistent logging (Fluent Bit sidecars, on by default for new clusters); log rotation; **declarative logical replicas (tech preview)**; extra volumes; custom cert-manager issuer; pgBouncer mTLS and pause/resume; pgBackRest repo auto-grow; **community PG images supported**; PG 19 tech preview; RKE2 official; full ARM64; PMM2 removed |

Cadence: 6 feature releases in about 18 months, one every 2 to 4 months. Patch releases are rare (one patch train, 2.8.x). The 3.1.0 notes say "Operator 2.8.0 and all 2.8.x patch releases have reached end of life". The exact support window per Percona version is **unverified**; the docs only point to an "Operator and CRD compatibility" table in update-operator.

**CloudNativePG:**

| Version | Date | Notes |
|---|---|---|
| 1.26.0 (rc1 2025-03-28, rc2 04-16, rc3 05-13) | 2025-05-23 | In-place major upgrades via pg_upgrade (offline); in-tree Barman deprecated in favour of the plugin (CNPG-I) |
| 1.25.2 / 1.24.4 | 2025-05-23 | patches |
| 1.26.1 / 1.25.3 | 2025-07-25 | patches |
| 1.27.0 (rc1 07-29) | 2025-08-12 | Quorum failover (experimental) and others |
| 1.27.1 / 1.26.2 / 1.25.4 | 2025-10-23 | patches |
| 1.28.0 (rc1 11-07, rc2 11-28) | 2025-12-09 | Quorum-based failover stable; declarative FDW management |
| 1.27.2 / 1.26.3 | 2025-12-09 | patches |
| 1.28.1 / 1.27.3 | 2026-02-05 | patches |
| 1.29.0 (rc1 03-13) | 2026-04-01 | Extensions in image catalogs, `podSelectorRefs` for pg_hba, shared ServiceAccount |
| 1.28.2 / 1.27.4 | 2026-04-01 | patches |
| 1.29.1 / 1.28.3 | 2026-05-08 | patches |
| 1.30.0 (rc1 06-19) | 2026-06-29 | **Primary `Lease` for safe promotion**; `DatabaseRole` CRD; TLS client certs for roles; Pooler image catalogs; VPA/HPA scale subresource; in-tree Barman removal moved to **1.31.0** |
| 1.29.2 / 1.28.4 | 2026-06-29 | patches |
| 1.29.3 / 1.30.1 | 2026-09-23 | patches |

Cadence: a minor release roughly every 3 to 4 months, each preceded by an RC. Patches ship on 2 or 3 supported branches at the same time, about every 1.5 to 2.5 months. The published policy is that a minor is "supported until 3 months after the N+1 minor release". The supported-releases page contradicts itself on cadence: it says "every three months" in one place and "approximately every two months" in another.

### 1.3 Supported PostgreSQL and Kubernetes

| | Percona 3.1.0 | CNPG 1.30 |
|---|---|---|
| PostgreSQL | Percona Distribution 14.24, 15.19, 16.15, 17.11.1, 18.6.1 (default 18). Community images: 14.24, 15.19, 16.15, 17.11, 18.6, and **19 tech preview** (UBI 9 only). PG 13 removed in 2.9.0. | 14 to 18 per the support table (main branch lists 13 to 18). Image catalogs reference 15.14, 16.10, 17.6 and 18.6 "system-trixie" images. |
| Kubernetes, officially tested | GKE 1.34 to 1.35; EKS 1.34 to 1.36; AKS 1.34 to 1.36; **OpenShift 4.19.43 to 4.22.10**; Minikube 1.38.1 (k8s 1.35.1); **RKE2 1.34 to 1.36** (new in 3.1.0). "Designed for compatibility with all CNCF-certified distributions." | Supported: k8s 1.34, 1.35, 1.36. "Tested, but not supported": 1.37, 1.33, 1.32, 1.31. "The CloudNativePG community does not officially support or test any Kubernetes distributions beyond the standard/vanilla one – such as Red Hat OpenShift." For OpenShift it points to EDB's certified operator. |
| Arch | x86_64 and ARM64 (full ARM64 support in 3.1.0; digests published) | Multi-arch images; the plugin docs have a "Supported Architectures" section. Exact arch list **unverified**. |
| Base images | Red Hat UBI 8, 9 (default) and 10 for Percona certified images. Operator base image moved to RHEL 10 in 2.9.0. | Debian (`trixie`/`bookworm`), in `minimal`, `standard` and `system` flavours at `ghcr.io/cloudnative-pg/postgresql` |

### 1.4 License and governance

| | Percona | CNPG |
|---|---|---|
| License | Apache 2.0. `LICENSE.md` reads "Copyright 2017-2025 Crunchy Data… 2021-2025 Percona… Licensed under the Apache License, Version 2.0". GitHub's license detector reports "Other/NOASSERTION" because the file is non-standard. This is cosmetic, but scanners may flag it. | Apache 2.0. Docs are CC-BY-4.0 (SPDX headers). |
| Governance | Single vendor (Percona). Fork of Crunchy Data PGO v5. Issues are tracked mainly in Percona Jira (K8SPG), with GitHub issues secondary. | **CNCF Sandbox, accepted 2025-01-21** (cncf/landscape `landscape.yml`). Governance repo `cloudnative-pg/governance`. **All 5 listed maintainers are EDB employees** (Bartolini, Canovai, Cecchi, Nenciarini, Ruocco). Originally created by EDB (2nd Quadrant). ADOPTERS.md has about 54 table rows. |
| Related CNCF project | **OpenEverest** (formerly Percona Everest) was accepted to the CNCF Sandbox on **2026-03-15** (landscape.yml; cncf/sandbox#450 gitvote passed). It uses `openeverest/provider-percona-postgresql`, i.e. the Percona PG operator. There is **no CNPG provider yet**; openeverest/openeverest#2256 "[DB] Add support for PostgreSQL backed by CloudNative PG" is open. | |

### 1.5 GitHub metrics (2026-10-13, unauthenticated API)

| Metric | percona/percona-postgresql-operator | cloudnative-pg/cloudnative-pg | cloudnative-pg/plugin-barman-cloud |
|---|---|---|---|
| Stars | 385 | **9,443** | 200 |
| Forks | 83 | 789 | 82 |
| Open issues + PRs (repo counter) | 51 (27 issues, 24 PRs) | 436 (206 issues, 230 PRs) | 145 |
| Contributors (anon=1, Link `last` page) | ~105 (includes Crunchy upstream history) | ~251 | ~28 |
| Issues opened in last 12 months | 29 | 879 | n/a |
| PRs merged in last 12 months | 366 | 1,497 | n/a |
| Repo created | 2021-03-04 | 2022-03-10 (public); the project dates from 2019/2020 inside EDB | 2024-09-24 |
| Other tracker | Jira K8SPG: about **324 unresolved** issues, 69 of them bugs (Jira approximate-count API) | GitHub only | |

For reference, CrunchyData/postgres-operator has 4,452 stars and 685 forks.

### 1.6 Commercial support

- **Percona:** Percona Support subscriptions and Managed Services for the Percona operator (docs `get-help.md`). **Notable:** Percona is now also listed as a **commercial support provider for CloudNativePG** on https://cloudnative-pg.io/support/ (added to the site repo on 2026-09-09, PR #462, file `content/support/percona.md`). The landing page https://www.percona.com/postgresql/cloudnativepg/ offers CNPG incident response, lifecycle and architecture guidance, migration, and monitoring with PMM and "Percona Coroot Edition". That page does not mention Percona's own operator or Everest.
- **EDB:**
  - EDB Postgres for Kubernetes / "EDB CloudNativePG Cluster" is the commercial build of CNPG, with an OpenShift-certified operator (the CNPG docs link to the Red Hat catalog entry 653fd4035eece8598f66d97b).
  - **EDB Postgres AI for CloudNativePG Global Cluster** (PGD4K) v2.0.0 was released 2026-03-26 (v2.0.1 is current). It runs EDB Postgres Distributed 6.x (multi-master) on k8s 1.33 to 1.35 and PG 14 to 18 (EDB docs).
- **Other CNPG support vendors listed on cloudnative-pg.io/support:** Axians, B1 Systems, CloudRaft, CYBERTEC, Dalibo, Data Bene, EDB, Linux Polska, Nibble-IT, Optimadata, Percona, PG Support, pgEdge, Procedure, Verito Digital (15 total). The CNPG failure-modes page says "If you are running CloudNativePG in production, we strongly recommend seeking professional support" and "Do not perform manual operations without professional support".
- **Solanica:** a company formed by Sergey Pronin and Peter Zaitsev to support OpenEverest (press: SD Times, The New Stack, LinuxInsider).

---

## 2. Architecture per the docs

### 2.1 HA mechanism
- **Percona:**
  - Patroni 4.1.5 (Percona 3.1.0 notes) runs inside each instance pod and handles leader election and automated failover.
  - The design is inherited from Crunchy PGO v5. Patroni uses the Kubernetes API as its DCS: the code in `internal/patroni/config.go` sets `kubernetes: {use_endpoints: true}`, so there is no etcd. **The Percona docs never say this explicitly.**
  - Default topology from `deploy/cr.yaml`: 3 PG instances, 3 pgBouncer, 1 pgBackRest repo-host.
  - Pod labels still use the `postgres-operator.crunchydata.com/*` prefix, even after the 3.0 API-group rename.
- **CNPG:**
  - Uses its own instance manager (PID 1 in each pod) and the operator's reconcile loop. There is no Patroni and no etcd; the Kubernetes API server is the source of truth.
  - **New in 1.30:** a Kubernetes `Lease` named after the cluster gates promotion. Defaults: `leaseDurationSeconds 15`, `renewDeadlineSeconds 10`, `retryPeriodSeconds 2`, `releasedLeaseDurationSeconds 1`.
  - A primary isolation check is on by default: the liveness probe fails if the pod can reach neither the API server nor its peers.
  - Pods are managed directly rather than through StatefulSets; each instance is `<cluster>-N`.

### 2.2 Failover behaviour and tunables
- **Percona / Patroni:**
  - `patroni.leaderLeaseDurationSeconds` (default 30) maps to Patroni `ttl`. `patroni.syncPeriodSeconds` (default 10) maps to Patroni `loop_wait`; the probe timings are derived from it.
  - `patroni.dynamicConfiguration` passes arbitrary Patroni settings (e.g. `synchronous_mode`, `synchronous_node_count`, `maximum_lag_on_failover`, slots).
  - Manual switchover uses `patroni.switchover.enabled/targetInstance` plus the `postgres-operator.crunchydata.com/trigger-switchover` annotation.
  - `patroni.createReplicaMethods` controls replica creation (pgBackRest or basebackup).
  - Synchronous replication is documented only through Patroni `dynamicConfiguration`.
  - **Docs error:** the CR reference (`operator.md#patronileaderleasedurationseconds`) says leaderLeaseDurationSeconds is the "Initial delay for liveness/readiness probes". It is actually the Patroni leader TTL. syncPeriodSeconds is described only as the probe period.
- **CNPG:**
  - `.spec.failoverDelay` (default 0 s) and `.spec.switchoverDelay` (the fast-shutdown timeout for the old primary).
  - `.spec.smartShutdownTimeout` (default 180 s); `.spec.primaryLease.*`; quorum-based failover via `.spec.postgresql.synchronous.failoverQuorum` (stable since 1.28).
  - `primaryUpdateStrategy` is `unsupervised` (default) or `supervised`. `primaryUpdateMethod` is `restart` (default) or `switchover`.
  - Synchronous replication is set with `.spec.postgresql.synchronous` (`method: any|first`, `number`). The sample cluster-example.yaml already enables `any 1`.
  - The docs give explicit **node-failure timing**: the primary is seen as unready about 40 to 55 s after the node becomes unreachable (node-monitor-grace-period), then `failoverDelay` applies.
  - The troubleshooting page warns that replicas can take about 127 s to reconnect after a failover if SYN packets are silently dropped. The fix is `STANDBY_TCP_USER_TIMEOUT`.

### 2.3 Backup tooling
- **Percona:**
  - pgBackRest 2.59.x, with up to 4 repos (`repo1`..`repo4`). Targets: S3 and S3-compatible (path-style option), GCS, Azure, PVC on the repo-host.
  - Full, differential and incremental backups; scheduled backups via cron in `backups.pgbackrest.repos[].schedules`; retention; encryption; async archiving.
  - The default cr.yaml has a `repo1` PVC repo on the repo-host and `full: "0 0 * * 6"`, so backups work out of the box to a local PVC.
  - PVC (CSI) snapshot backups have been tech preview since 2.9.0, with no automatic retention.
  - CRDs: `PerconaPGBackup` (`pg-backup`) and `PerconaPGRestore` (`pg-restore`). Backups can be disabled (`backups.enabled: false`, 2.7.0+). `status.size` on backups since 3.1.0.
- **CNPG:**
  - Pluggable through CNPG-I. The official object-store path is the **Barman Cloud Plugin** (separate deployment in `cnpg-system`, **requires cert-manager**, CNPG ≥ 1.26). It uses an `ObjectStore` CRD (`barmancloud.cnpg.io/v1`) and `.spec.plugins` on the Cluster.
  - The in-tree `.spec.backup.barmanObjectStore` is deprecated since 1.26 and, per the 1.30.0 notes, will be **removed in 1.31.0**. `Backup.spec.method` still defaults to `barmanObjectStore` for backward compatibility.
  - Native `volumeSnapshot` backups are supported (hot or cold, can be incremental depending on the CSI driver).
  - Backups run from a standby by default (`target: prefer-standby`). `ScheduledBackup` CRD with a 6-field cron. No default backups are configured.

### 2.4 Restore and PITR
- **Percona:**
  - **In-place restore** into the running cluster via `PerconaPGRestore`. It is destructive and the default is the latest backup; `--set=<label>` picks a backup, `--type=time --target=...` does PITR.
  - **Clone** to a new cluster via `spec.dataSource.postgresCluster | pgbackrest | volumes`.
  - `status.latestRestorableTime` is tracked on backups (`backups.trackLatestRestorableTime`).
  - PITR is also possible from PVC snapshots.
- **CNPG:**
  - **No in-place restore.** "Recovery is not performed in-place on an existing cluster. Instead, it is used to bootstrap a new cluster" (`bootstrap.recovery`).
  - Sources: Barman plugin (`externalClusters[].plugin` with `barmanObjectName`), VolumeSnapshots, or a `Backup` object.
  - PITR targets are `targetTime`, `targetLSN`, `targetXID`, `targetName` and `targetImmediate`, with an optional `backupID`.

### 2.5 Connection pooling
- **Percona:** pgBouncer is built in (`proxy.pgBouncer`, 3 replicas by default; set to 0 to disable).
  - The `cluster1-pgbouncer` service is the default endpoint. `cluster1-ha` points to the primary and `cluster1-replicas` to the replicas.
  - Superusers are not exposed through pgBouncer by default (`exposeSuperusers: false` since 2.9.0).
  - 3.1.0 added pgBouncer mTLS with extra trusted CAs, declarative pgBouncer users, and pause/resume.
- **CNPG:** a separate `Pooler` CRD (PgBouncer) of type `rw` or `ro`, with PodMonitor and metrics (TLS metrics in 1.30) and pause/resume.
  - 1.30 added image catalogs for the Pooler.
  - Built-in services: `<cluster>-rw`, `-ro`, `-r`.

### 2.6 Monitoring
- **Percona:**
  - **PMM 3** client sidecar (PMM 3.9.1; PMM2 removed in 3.1.0). It is disabled by default (`pmm.enabled: false`). Patroni metrics go to PMM (2.8.0).
  - A Prometheus `postgres_exporter` is documented only as a **user-added custom sidecar**; "The Operator does not deploy postgres_exporter for you".
  - `pg_stat_monitor` is disabled by default since 2.9.0; `pg_stat_statements` is optional.
  - Persistent logs via Fluent Bit (3.1.0).
  - `monitor-kubernetes.md` covers k8s monitoring with PMM.
- **CNPG:**
  - A native Prometheus exporter on port 9187 in every instance, with custom queries via ConfigMaps or Secrets. Operator metrics are also exposed.
  - Users are told to create a `PodMonitor` manually; the old `enablePodMonitor` field is discouraged. The Helm chart can create one.
  - Grafana dashboard and PrometheusRules are supplied through the quickstart's kube-prometheus-stack section and a separate grafana-dashboards repo.
  - JSON logs go to stdout.

### 2.7 Extensions
- **Percona:**
  - Built-in toggles under `spec.extensions`: pg_stat_monitor, pg_stat_statements, pg_audit (on), pgvector, pg_repack, pg_cron, set_user, pg_tde.
  - **Custom extensions** are downloaded as tar packages from S3 or S3-compatible storage at runtime (since 2.3). The docs warn this "may violate immutability".
  - PostGIS images are available. Known limitation: on RKE2, enabling custom extensions restarts pods and can leave a diverged former primary.
- **CNPG:**
  - **Image Volume extensions** require PG 18+ and Kubernetes 1.35+ (1.33 to 1.34 need the feature gate), plus containerd ≥ 2.1 or CRI-O ≥ 1.31.
  - Extensions can be declared in `ImageCatalog` (1.29). Extensions inside each database are managed declaratively by the `Database` CRD (`.spec.extensions`).
  - Otherwise you build a custom image (the `system` and `standard` images carry common extensions).
  - pg_upgrade with image-volume extensions works only for targets of PG 19 or later (1.30).

### 2.8 TDE / encryption at rest
- **Percona:** `pg_tde` (3.1.0), on Percona Distribution 17 and 18 only, not on community images.
  - It covers tables, indexes and temp files, with optional WAL encryption. Vault KV v2 is the only key provider for now; KMIP is planned.
  - Not compatible with logical replicas. Backups work when the key is reachable.
- **CNPG:** "CloudNativePG delegates encryption at rest to the underlying storage class" (security.md). There is no TDE in community PostgreSQL. EDB's commercial images have TDE in EDB Postgres Advanced/Extended; the CNPG docs do not cover this, so it is **unverified here**.

### 2.9 Major version upgrades
- **Percona:** `PerconaPGUpgrade` CR (`deploy/upgrade.yaml`), GA since 2.9.0. It uses a special upgrade image (`percona-distribution-postgresql-upgrade:18.6-17.11-16.15-15.19-14.24-3`).
  - The upgrade is **offline**: the whole cluster is paused. Data is duplicated on each PVC and the old data must be removed manually (`rm -rf /pgdata/pg17`).
  - pgaudit must be dropped and recreated in each database. A UBI change requires a collation check. Logical replicas are invalidated.
- **CNPG:** three methods.
  1. Logical dump/restore via `bootstrap.initdb.import`, offline.
  2. Logical replication (`Publication`/`Subscription`), online blue/green.
  3. **Offline in-place pg_upgrade (1.26+)**, triggered declaratively by changing `imageName` (or the image catalog major). Source and target must use the same OS distro (e.g. not bullseye to bookworm).
  - Warning in the docs: PG 17.0 to 17.5 fails if `max_slot_wal_keep_size` ≠ -1.

### 2.10 DR across Kubernetes clusters
- **Percona:** standby clusters (`spec.standby.enabled`) of three kinds: repo-based (pgBackRest repo in object storage), streaming (host/port plus shared custom TLS certs), or both.
  - Lag detection via `standby.maxAcceptableLag` (2.9.0).
  - Promotion means setting `standby.enabled: false`. The docs say you must ensure the old primary is down to avoid split-brain, and that automated cross-site failover "is outside of the Operator's scope".
  - Delayed replicas are **not supported** (limitations page).
- **CNPG:** replica clusters (`.spec.replica`, `externalClusters`), sourced from an object store and/or streaming.
  - **Distributed topology** lets you do a controlled, declarative demotion and promotion across clusters via `.spec.replica.primary` / `source`, without a full re-clone.
  - Delayed replicas are supported (`recovery_min_apply_delay`).

### 2.11 Declarative roles and databases
- **Percona:** `spec.users[]` (name, databases, options, secretName, password) creates roles and databases and generates `<cluster>-pguser-<user>` secrets with `uri` and `pgbouncer-uri`. There is no separate Database or Role CRD.
- **CNPG:**
  - `.spec.managed.roles` (inline) plus the **`DatabaseRole` CRD (1.30)**, which can issue TLS client certs.
  - The **`Database` CRD** manages databases, extensions, schemas, FDWs and servers.
  - `bootstrap.initdb` creates the `app` database and user (`<cluster>-app` secret).

### 2.12 kubectl plugin
- **Percona:** **none.** There is no Percona kubectl plugin in the docs. Operations use plain `kubectl`, `patronictl` via exec, and `pgbackrest` via exec.
- **CNPG:** `kubectl cnpg`, installable via script, deb/rpm, AUR, krew or Homebrew. Subcommands: status, promote, restart, reload, maintenance, report (operator/cluster, `--logs`), logs (pretty), destroy, hibernate, pgbench, fio, backup, psql, snapshot, pgadmin4, publication/subscription create/drop, sequence sync, `install generate`. It also integrates with k9s.

### 2.13 Images and distributions
- **Percona:** Percona Distribution for PostgreSQL (UBI-based, includes pg_stat_monitor, pgAudit, pg_tde, pg_repack and others), PostGIS variants, and since 3.1.0 community PostgreSQL images. Registry is `docker.io/percona/*`; the operator image is `percona/percona-postgresql-operator:3.1.0`.
- **CNPG:** `ghcr.io/cloudnative-pg/postgresql:<ver>-<minimal|standard|system>-<trixie|bookworm>`; `ImageCatalog` and `ClusterImageCatalog` CRDs.

### 2.14 Security / TLS
- **Percona:**
  - TLS is on by default through the operator's internal PKI. cert-manager automation since 2.9.0; custom Issuer or ClusterIssuer since 3.1.0; `tlsCertManagementPolicy` (`userProvidedOnly`).
  - Docs exist for migrating to and from cert-manager.
  - LDAP (2.9.0). Works with `readOnlyRootFilesystem` and OpenShift restricted-v2.
- **CNPG:**
  - Operator-managed CA by default, or user-provided certificates, including cert-manager. Client-cert auth for `streaming_replica`; `DatabaseRole` client certs.
  - LDAP via `.spec.postgresql.ldap`; `podSelectorRefs` for dynamic pg_hba (1.29).
  - Security docs cover the restricted PSS, seccomp, and the operator's RBAC.

### 2.15 Storage
- **Percona:** PVCs for data, a separate optional WAL volume, tablespaces, and the pgBackRest repo PVC. Volume expansion works, and **auto-grow** is available via the `AutoGrowVolumes` feature gate for data and, since 3.1.0, repo volumes. Huge pages are supported.
- **CNPG:** PGDATA PVC, optional separate WAL PVC, declarative tablespaces, PVC resize. **No auto-grow** (Percona's compare page agrees: "Manual"). Volume-snapshot clones are supported.

### 2.16 Fencing and hibernation
- **Percona:** `spec.pause: true` gracefully stops the cluster (primary, replicas, pgBackRest and jobs). There is no per-instance fencing feature; per-pod maintenance is manual (`manage-manually.md`, sleep-forever / probe disable).
- **CNPG:** **fencing** of one, several or all instances via the `cnpg.io/fencedInstances` annotation or `kubectl cnpg fencing`. **Declarative hibernation** via `cnpg.io/hibernation=on` (PVCs are kept, pods removed). There is also `cnpg.io/reconciliationLoop: disabled` for emergencies.

### 2.17 Logical replication
- **Percona:** 3.1.0 adds **declarative "logical replicas" (tech preview, PG 17+)**. These are read-only pods fed by logical replication with their own Service; Patroni does not promote them.
  - Failover often breaks them (slots missing) and they must be reseeded. In-place restore and major upgrade invalidate them, and they cannot be combined with TDE.
  - There are no Publication or Subscription CRDs.
- **CNPG:** `Publication` and `Subscription` CRDs, plus plugin commands. The docs include a worked live-migration and major-upgrade example using logical replication.

### 2.18 Install scope, Helm and OLM
- **Percona:**
  - The default is namespace-scoped (`deploy/bundle.yaml`). Cluster-wide mode uses `cw-bundle.yaml` (`WATCH_NAMESPACE`).
  - Helm charts are `percona/pg-operator` and `percona/pg-db`.
  - OLM: Red Hat Certified Operator plus community catalog. 3.0.0 fixed `OperatorGroup` namespace scoping, and all-namespace mode was added to the certified "stable" channel. Red Hat Marketplace listings stopped in 2.9.0.
- **CNPG:**
  - The default is cluster-wide (`WATCH_NAMESPACE` unset means all namespaces). Install into `cnpg-system` via the release manifest, or customise with `kubectl cnpg install generate --watch-namespace`.
  - Helm charts are `cnpg/cloudnative-pg`, `cnpg/cluster` and `cnpg/plugin-barman-cloud`.
  - OLM via OperatorHub.io. For OpenShift, the docs point to EDB's certified operator.

---

## 3. Documentation quality evaluation

### 3.1 Percona Operator for PostgreSQL docs
URL: https://docs.percona.com/percona-operator-for-postgresql/latest/ (about 144 markdown pages plus release notes; MkDocs Material).

**Structure and navigation.** The docs are task-oriented: Get started, Installation (one page per platform), Configuration, Management (backups, standby, upgrade, scaling, HA), Troubleshooting, Reference.
- The restore and backup pages include decision flowcharts and pros/cons tables (`backups-restore.md`).
- Migration-from-Crunchy guides (4 methods).
- Release notes are very detailed and include image digests.

**Quickstart.**
- `quickstart.md` → `kubectl.md` → connect → insert data → backup → PMM.
- The kubectl install is **4 steps**: create namespace, apply bundle, apply cr.yaml, `kubectl get pg`. Prerequisites (kubectl and a k8s cluster) are clearly stated and links are pinned to the version (`v3.1.0`).
- Caveat: the pinned cr.yaml deploys older image builds than the docs recommend (see 1.1).

**Install methods covered.** kubectl, Helm, OpenShift/OLM, Minikube, GKE, EKS, AKS, RKE2, generic Kubernetes, OpenEverest, cluster-wide, custom registry, community images.
- Minor gap: Helm prerequisites list Minikube, GKE and EKS but omit AKS.

**Backup and restore docs.** Strong: storage per backend, schedules, retention, encryption, PVC snapshots, in-place versus clone, PITR (in-place, clone and from snapshot), latest restorable time.
- Error: `backups-pitr-inplace.md` gives the time format as `<YYYY-MM-DD HH:MM:DD>`; the last field should be SS.

**Failure recovery and HA docs.** **Weak.**
- `ha-deploy.md` covers sizing, anti-affinity and synchronous replication, then spends most of its length on logical replicas.
- **No page describes what happens on primary pod failure or node failure**: detection time, Patroni TTL, how long until `-ha` moves, pg_rewind. The architecture page only says "Kubernetes automatically reschedules… Patroni handles which instance is primary".
- There is no failover-timing guidance or tunable explanation, and the CR reference misdescribes the Patroni timing fields (2.2).
- `reinit.md` and `manage-manually.md` are useful.

**Troubleshooting docs.** A dedicated section exists with 6 pages plus reinit: `troubleshoot-operator.md`, `debug.md`, `debug-storage.md`, `debug-shell.md`, `debug-logs.md`, `manage-manually.md`, `reinit.md`. Content is mostly generic kubectl (get, describe, logs, events, PVC/PV, exec) plus pprof and pgBackRest log level.
- No Patroni-specific troubleshooting: `patronictl list` appears only in reinit.
- No guide for a cluster stuck in `initializing`, a stuck restore or a failed backup.
- Errors found on the live site:
  - `debug-shell.html` shows `hostname` returning **`cluster1-pxc-0`**, copied from the PXC docs, and hard-codes `/pgdata/pg16/log` although the default is PG 18.
  - `troubleshoot-operator.html` says "The cluster should typically be in the `Running` state", but the PG CR status is `ready` per `cr-statuses.md`.
  - The privilege-check script is fetched from a personal gist (`gist.githubusercontent.com/cshiv/...`). Its sample output links the PXC operator to the PostgreSQL docs URL.
  - `kubectl describe <database-pod-name>` omits the resource type.

**CR reference completeness.** `operator.md` has about 366 option entries plus separate Backup, Restore and status references. It is hand-written, so it has accuracy gaps (Patroni timing fields; `leaderLeaseDurationSeconds` has no type/example table). There is no generated CRD API reference.

**Examples.** `deploy/cr.yaml` is heavily commented and there are per-feature YAML snippets. The few separate sample manifests are in `deploy/`.

**Version-specific docs.** Versioned paths exist (`/3.1.0/`, `/3.0/`) plus a legacy-docs archive. Release-note links use versioned URLs.

**Search.** MkDocs search plus a **Kapa "AI assistant"** on the page.

**Outdated content and other errors.**
- `compare.md` lists Percona as PG "13 - 18" although PG 13 was removed in 2.9.0. It shows CNPG as "Sidecar containers: No"; CNPG has had no general sidecar field (partly true), but its plugins do inject sidecars.
- The everest.md page says OpenEverest is a CNCF Sandbox project; this is correct (accepted 2026-03-15).

**Scores (1 to 10):** structure 8; quickstart 8; install coverage 9; backup/restore 8; HA/failure 5; troubleshooting 6; CR reference 7; examples 7; versioning 8; search 8. **Overall 7.4.**

### 3.2 CloudNativePG docs
URL: https://cloudnative-pg.io/docs/1.30/ (Docusaurus, migrated in 2026; about 65 pages plus appendixes and a generated API reference). The plugin docs are a separate site.

**Structure and navigation.** Concept-oriented, with long and dense pages (architecture, replication, failover, backup, recovery, replica clusters).
- Very deep on PostgreSQL internals and RPO/RTO.
- Backup and restore is split across three places: the operator docs, the plugin docs site, and the deprecated in-tree appendix. During the transition this is confusing.
- **The legacy URL `cloudnative-pg.io/documentation/current/*`**, which is widely linked and was given in our brief, now meta-refreshes to **`/docs/devel/*`** (development docs) rather than the latest stable `/docs/1.30/*`.

**Quickstart.** Kind or Minikube setup, then it **defers to the Installation page** for the operator install. You then apply `cluster-example.yaml`, which you must download from a docs asset link because the command assumes a local file. Part 4 sets up Prometheus and Grafana.
- Outdated content:
  - The `imageName` example uses `ghcr.io/cloudnative-pg/postgresql:13.6`, an unsupported major.
  - Minikube is "normally used in conjunction with VirtualBox".
- The quickstart is explicitly not for production. There are about 3 commands to a running cluster. It does not cover backup, which needs the plugin plus cert-manager plus an object store.

**Install methods covered.** Manifest (versioned URL), the `cnpg` plugin generator, Helm (link only: **no helm command in the operator docs**), OLM/OperatorHub, and dev snapshots. There are no cloud-specific (EKS/GKE/AKS) guides except a GKE webhook-firewall warning. OpenShift is deferred to EDB.

**Backup and restore docs.** Conceptually thorough: object store versus snapshots comparison, backup from standby, recovery targets, "how recovery works under the hood".
- The plugin site has its own troubleshooting and migration guides.
- No in-place restore, which is a feature gap rather than a docs gap.

**Failure recovery and HA docs.** **Excellent.**
- `failover.md` covers the two-phase failover, the primary Lease, isolation checks, node-failure detection timing (40 to 55 s), failoverDelay, quorum failover, and RTO/RPO impact.
- `failure_modes.md` was cut back to self-healing summaries and says "Do not perform manual operations without professional support".

**Troubleshooting docs.** One comprehensive `troubleshooting.md`:
- `cnpg status` and `cnpg report`, an emergency `pg_dump` backup, operator, cluster, pod, backup, storage, node and conditions info.
- How to wait for conditions, networking, core dumps, profiling.
- Known issues: storage full, Pending pods, replicas out of sync without backups, stuck in "Creating new replica", NetworkPolicies, bootstrap failures, 2-minute reconnect after failover.

**CR reference completeness.** The API reference (`cloudnative-pg.v1.md`) is **generated** and complete, and the plugin has its own generated reference.

**Examples.** About 82 sample manifests in `docs/src/samples`.

**Version-specific docs.** Versions 1.25 to 1.30 plus devel. But the `supported_releases` page on the **1.30 site** has stale and contradictory data:
- 1.29.x is "Currently supported: Yes" although its EOL of 29 Sep 2026 has passed.
- 1.31.0 is "~ Sep, 2026" and not released.
- `main` lists "13 - 18".
- The cadence is stated as both every two and every three months.

**Search.** Algolia DocSearch.

**Errors.** A **leftover LLM chat artifact** in the published docs: https://cloudnative-pg.io/docs/1.30/supported_releases/ contains the line "Sure, here's an improved version of the naming scheme section:" directly before the "Naming Scheme" heading. It is in the source too (`docs/src/supported_releases.md`) and was verified on the live site 2026-10-13.

**Scores (1 to 10):** structure 7; quickstart 6; install coverage 6; backup/restore 7; HA/failure 9; troubleshooting 8; CR/API reference 9; examples 9; versioning 6; search 7. **Overall 7.4.**

**Net:** the two are tied overall, with different strengths. Percona is better for task-oriented "how do I do X" content and platform install guides. CNPG is much better on HA internals, failure behaviour, troubleshooting depth and generated API reference. Percona's HA and failure documentation is the clearest gap and is easy to fix.

---

## 4. Feature comparison matrix

| # | Capability | Percona Operator for PG 3.1.0 | CloudNativePG 1.30 |
|---|---|---|---|
| 1 | License | Yes. Apache 2.0 (non-standard LICENSE.md file) | Yes. Apache 2.0 |
| 2 | Vendor-neutral governance | No. Single vendor (Percona) | Partial. CNCF Sandbox, but all maintainers are EDB |
| 3 | HA engine | Patroni (k8s endpoints DCS) | Native instance manager plus k8s Lease |
| 4 | External DCS (etcd) needed | No | No |
| 5 | Automated failover | Yes | Yes |
| 6 | Failover delay / tuning | Partial. Patroni ttl/loop_wait plus dynamicConfiguration; poorly documented | Yes. failoverDelay, switchoverDelay, primaryLease, smartShutdownTimeout |
| 7 | Quorum-based failover | Partial. Via Patroni synchronous_mode settings (not specifically documented) | Yes. failoverQuorum (stable 1.28) |
| 8 | Synchronous replication | Yes. Via Patroni dynamicConfiguration | Yes. `.spec.postgresql.synchronous` (on in the sample) |
| 9 | Manual switchover | Yes. CR fields plus annotation, 6 steps | Yes. `kubectl cnpg promote` |
| 10 | Primary update strategy control | Partial. Patroni-driven rolling restart; no supervised mode documented | Yes. supervised/unsupervised, restart/switchover |
| 11 | Built-in backup tool | Yes. pgBackRest (full/diff/incr, 4 repos) | Partial. Via a separate Barman Cloud plugin (needs cert-manager); in-tree deprecated, removed in 1.31 |
| 12 | Backups out of the box (local PVC) | Yes. repo1 PVC with weekly full by default | No. No backup until an object store or snapshots are configured |
| 13 | S3 / GCS / Azure | Yes | Yes (plugin) |
| 14 | Volume snapshot backups | Partial. Tech preview (2.9), no retention | Yes. GA, native |
| 15 | Backup from standby | Partial. pgBackRest backs up via the repo-host; standby backup not documented as such (unverified) | Yes. Default prefer-standby |
| 16 | PITR | Yes | Yes |
| 17 | In-place restore into the existing cluster | Yes. PerconaPGRestore | No. New cluster only |
| 18 | Clone / restore to a new cluster | Yes. dataSource (cluster/pgbackrest/volumes) | Yes. bootstrap.recovery / pg_basebackup |
| 19 | Connection pooler | Yes. pgBouncer built into the cluster CR | Yes. Separate Pooler CRD (rw/ro) |
| 20 | Pooler mTLS / pause | Yes (3.1.0) | Yes (pause; TLS metrics 1.30; client TLS) |
| 21 | Monitoring stack | Yes. PMM 3 sidecar (integrated QAN, dashboards) | Yes. Native Prometheus exporter, PodMonitor, Grafana dashboard |
| 22 | Prometheus-native metrics without extra tooling | Partial. Only via user-added postgres_exporter sidecar | Yes |
| 23 | Persistent / shipped logs | Yes. Fluent Bit sidecar (3.1.0) | Partial. JSON to stdout; ship with your own stack |
| 24 | TDE (encryption at rest in PG) | Yes. pg_tde, PG 17/18, Vault only | No. Storage-class only (EDB commercial: unverified) |
| 25 | Extension install without a custom image | Yes. Tar from S3 (any PG version) | Partial. ImageVolume, PG 18+ and k8s 1.33+/1.35+ |
| 26 | Bundled extras (pg_stat_monitor, pgAudit, pg_repack, pgvector, pg_cron, PostGIS) | Yes. In Percona Distribution images | Partial. Depends on image flavour; PostGIS images available |
| 27 | Major version upgrade, in-place | Yes. PerconaPGUpgrade CR (offline, GA 2.9) | Yes. Change imageName (offline pg_upgrade, 1.26+) |
| 28 | Major upgrade, online/logical | Partial. Logical replicas (tech preview), not positioned for upgrades | Yes. Documented Publication/Subscription blue-green |
| 29 | Minor upgrade | Yes. Image change, rolling | Yes. Image or catalog change, rolling |
| 30 | Cross-k8s DR replica cluster | Yes. Standby cluster (repo/streaming/both) | Yes. Replica clusters |
| 31 | Declarative cross-cluster switchover (no re-clone) | No. Promote by disabling standby; old primary must be rebuilt | Yes. Distributed topology |
| 32 | Delayed replicas | No (documented limitation) | Yes |
| 33 | Declarative roles | Partial. `spec.users` inline | Yes. Inline managed roles plus DatabaseRole CRD |
| 34 | Declarative databases | Partial. Via `spec.users[].databases` | Yes. Database CRD (extensions, schemas, FDWs) |
| 35 | Logical replication CRDs | Partial. Logical replicas (tech preview); no Publication/Subscription CRDs | Yes. Publication/Subscription CRDs |
| 36 | kubectl plugin | No | Yes. `kubectl cnpg` |
| 37 | Fencing (per instance) | No | Yes |
| 38 | Hibernation / pause | Yes. `spec.pause` | Yes. Declarative hibernation |
| 39 | Storage auto-grow | Yes. AutoGrowVolumes feature gate (data and repo) | No. Manual resize |
| 40 | Separate WAL volume / tablespaces | Yes / Yes | Yes / Yes (declarative tablespaces) |
| 41 | TLS by default / cert-manager | Yes / Yes (custom issuer 3.1) | Yes / Yes |
| 42 | LDAP auth | Yes (2.9) | Yes |
| 43 | Cluster-wide install | Yes. cw-bundle (default namespaced) | Yes. Default cluster-wide |
| 44 | Helm charts | Yes. pg-operator plus pg-db | Yes. cloudnative-pg, cluster, plugin-barman-cloud |
| 45 | OperatorHub / OLM | Yes. Red Hat Certified plus community | Partial. OperatorHub.io community; Red Hat certified only via EDB |
| 46 | OpenShift officially tested | Yes. 4.19 to 4.22 | No (community). Yes via EDB commercial |
| 47 | ARM64 | Yes (3.1.0) | Yes (multi-arch; unverified detail) |
| 48 | Community PG images supported | Yes (3.1.0) | Yes (its own community images) |
| 49 | PG 19 preview | Yes. Tech preview (community image) | No. Not in the 1.30 support table |
| 50 | Web UI / DBaaS layer | Yes. OpenEverest (CNCF Sandbox) uses the Percona operator | No. No official UI; EDB Postgres AI platform is commercial |
| 51 | Multi-master / distributed writes | No | No. EDB PGD4K "Global Cluster" is commercial |
| 52 | Migration path from Crunchy PGO | Yes. 4 documented methods; CRD rename allows coexistence | Partial. Generic import/logical replication |
| 53 | VPA/HPA scale subresource | Unverified | Yes (1.30) |

---

## 5. Competitive positioning notes

### Where Percona is stronger
- **Batteries included.** pgBackRest backups work on day one to a repo-host PVC, pgBouncer is in the same CR, and PMM gives one-flag monitoring with query analytics. CNPG needs a separate plugin, cert-manager and an object store before the first backup.
- **In-place restore and PITR** on the same cluster with the same endpoints. CNPG cannot do this; restore always means a new cluster and an endpoint cutover. This is a strong point for DBAs used to VM-era tooling.
- **pgBackRest:** a mature tool with full, differential and incremental backups, parallelism, multiple repos, and encryption in a familiar format. Barman Cloud is a capable tool too, but backup through the plugin is a new path (v0.x).
- **TDE with pg_tde:** a unique open-source TDE. This matters for compliance-driven buyers in finance, healthcare and the EU.
- **Platform certification and testing:** OpenShift (Red Hat Certified, tested 4.19 to 4.22), EKS, GKE, AKS and RKE2 are all release-tested. The CNPG community officially tests vanilla k8s only and sends OpenShift users to EDB.
- **Extensions without rebuilding images** on any PG version, plus a rich bundled set (pg_stat_monitor, pgAudit, pg_repack, pgvector, pg_cron, set_user, PostGIS).
- **Storage auto-grow.**
- **Crunchy migration story:** coexists with PGO after the 3.0 CRD rename. This targets Crunchy users, especially after Crunchy's change of ownership (**unverified** current Crunchy status).
- **OpenEverest:** a GUI/DBaaS layer that uses Percona operators. The PG provider is Percona's; there is no CNPG provider yet (issue #2256 open).
- **No vendor capture concerns:** Percona does not sell a proprietary PG fork. CNPG's maintainers are all EDB, and EDB upsells its EDB Postgres Advanced/Extended images and PGD.

### Where CNPG is stronger
- **Mindshare:** 9.4k stars versus 385, about 2.4x the contributors, 1,497 merged PRs versus 366 in the last year, CNCF Sandbox status, and a large adopter list. Many teams default to CNPG.
- **Kubernetes-native design** with no Patroni layer and an API-server-driven state. Some users see Patroni-in-a-pod as "legacy/VM-style", which is a common objection.
- **Feature breadth for day-2 operations:**
  - fencing, hibernation, distributed topology and declarative cross-cluster switchover, delayed replicas;
  - Database, DatabaseRole, Publication and Subscription CRDs;
  - image catalogs and ImageVolume extensions;
  - native Prometheus metrics, quorum failover and the primary lease.
- **`kubectl cnpg` plugin:** status, report, promote, psql, backup and hibernate in one tool. Percona has no CLI.
- **Documentation depth on HA and failure behaviour,** plus a generated API reference.
- **Release discipline:** RCs before each minor, parallel patch branches, and a published support policy.
- **Commercial ecosystem:** 15 listed support vendors. **Percona itself is listed as a CNPG support provider since 2026-09-09**, which muddies Percona's "use our operator" message.

### Percona weaknesses and gaps to expect in deals
- Low GitHub community signal; most issues live in Jira (about 324 open in K8SPG).
- Crunchy heritage shows: `postgres-operator.crunchydata.com` labels and annotations are still in use, and the switchover annotation is Crunchy-named.
- Several headline features are tech preview: PVC snapshots, logical replicas, PG 19.
- Major upgrade is offline, needs double the disk space and requires manual cleanup.
- No fencing and no delayed replicas; cross-site promotion is manual and the old primary must be rebuilt.
- HA and failover documentation is thin and has errors.
- Quickstart image tags lag behind the docs' recommended rebuilt images.

### Likely customer objections and responses

| Objection | Response |
|---|---|
| "CNPG is the community standard / CNCF" | OpenEverest is also CNCF Sandbox and uses the Percona operator. Percona is Apache 2.0 with no open-core upsell. CNPG maintainers are 100% EDB. |
| "Patroni inside a pod is an extra moving part" | Patroni is the most widely deployed PG HA manager. Percona uses the k8s DCS, so there is no etcd, and many DBAs already know `patronictl`. |
| "Why can't I just use CNPG and get support from Percona?" | We can (Percona now lists CNPG support). Position the operator on TDE, in-place restore, pgBackRest, PMM, OpenShift certification, auto-grow and the Everest UI. |
| "CNPG has a kubectl plugin and better troubleshooting docs" | A real gap. Recommend Percona invest in a CLI or plugin and in failure-mode docs. |
| "Backups require a plugin and cert-manager in CNPG" | Percona advantage: backups work out of the box. |

### Recommendations for Percona docs (quick wins)
1. Add a "Failure scenarios" page: what happens on primary pod deletion, node loss, network partition and storage loss; the expected failover time with default Patroni ttl 30 / loop_wait 10; which Services move; how a former primary rejoins (pg_rewind or reinit).
2. Fix the `patroni.leaderLeaseDurationSeconds` and `syncPeriodSeconds` descriptions in the CR reference and explain the Patroni mapping (ttl/loop_wait) and the k8s DCS.
3. Fix `debug-shell` (pxc hostname, pg16 path) and `troubleshoot-operator` (`Running` should be `ready`; move the privilege-check script out of a personal gist; fix the PXC link in its sample output).
4. Update `compare.md` (PG 14 to 18, not 13 to 18).
5. Update `deploy/cr.yaml` image tags when images are rebuilt, or note the gap in the quickstart.
6. Add a troubleshooting page for a stuck cluster, restore or backup with Patroni and pgBackRest commands.

---

## 6. Docs-prescribed procedures (for the hands-on tester)

### 6.1 Install commands (as the docs and charts prescribe, 2026-10-13)

**Percona (kubectl, `kubectl.md`):**
```bash
kubectl create namespace postgres-operator
kubectl apply --server-side -f https://raw.githubusercontent.com/percona/percona-postgresql-operator/v3.1.0/deploy/bundle.yaml -n postgres-operator
kubectl apply -f https://raw.githubusercontent.com/percona/percona-postgresql-operator/v3.1.0/deploy/cr.yaml -n postgres-operator
kubectl get pg -n postgres-operator      # expect STATUS ready; cluster name cluster1
```
- **Default manifest:** `deploy/cr.yaml`, which creates `PerconaPGCluster` **`cluster1`**: PG 18, 3 instances (`instance1`), 3 pgBouncer, repo1 PVC 1Gi, weekly full Sat 00:00, PMM off, Fluent Bit logs on.
- Other manifests: `deploy/backup.yaml` (backup1), `deploy/restore.yaml` (restore1), `deploy/upgrade.yaml`, `deploy/cw-bundle.yaml` (cluster-wide).
- Images pinned in v3.1.0 cr.yaml: `percona/percona-distribution-postgresql:18.6.1-1`, `percona/percona-pgbouncer:1.25.2-6`, `percona/percona-pgbackrest:2.59.0-1`, `percona/fluentbit:5.1.1-1`, `percona/pmm-client:3.9.1`. The docs recommend 18.6.1-3, 1.25.2-8 and 2.59.1-2.

**Percona (Helm, `helm.md`):**
```bash
helm repo add percona https://percona.github.io/percona-helm-charts/
helm repo update
kubectl create namespace <my-namespace>
helm install my-operator percona/pg-operator --namespace <my-namespace>   # chart 3.1.0
helm install cluster1 percona/pg-db -n <my-namespace>                      # chart 3.1.0
kubectl get pg -n <my-namespace>
```

**Percona connect (`connect.md`):**
```bash
PGBOUNCER_URI=$(kubectl get secret cluster1-pguser-cluster1 -n <ns> -o jsonpath='{.data.pgbouncer-uri}' | base64 --decode)
kubectl run -i --rm --tty pg-client --image=percona/percona-distribution-postgresql:18.6.1-3 --restart=Never -- psql $PGBOUNCER_URI
```

**CNPG (manifest, `installation_upgrade` 1.30):**
```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml
kubectl rollout status deployment -n cnpg-system cnpg-controller-manager
```

**CNPG (Helm, from the charts repo README; the operator docs only link to it):**
```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm upgrade --install cnpg --namespace cnpg-system --create-namespace cnpg/cloudnative-pg   # chart 0.29.1 / app 1.30.1
```
The deployment is named `cnpg-cloudnative-pg` with Helm and `cnpg-controller-manager` with the manifest.

**CNPG cluster (quickstart):**
- Download the `cluster-example.yaml` sample (it is the same as https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/docs/src/samples/cluster-example.yaml), then `kubectl apply -f cluster-example.yaml`.
- This creates Cluster **`cluster-example`**: 3 instances, `synchronous: {method: any, number: 1}`, storage 1Gi, default image `ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie`.
- Pods are `cluster-example-1..3`. Services are `cluster-example-rw/-ro/-r`. Secret is `cluster-example-app`.

**CNPG kubectl plugin:**
```bash
curl -sSfL https://github.com/cloudnative-pg/cloudnative-pg/raw/main/hack/install-cnpg-plugin.sh | sudo sh -s -- -b /usr/local/bin
# or: kubectl krew install cnpg   |  brew install kubectl-cnpg
```

**Barman Cloud plugin (needed for object-store backups; requires cert-manager and CNPG ≥ 1.26; install into `cnpg-system`):**
```bash
kubectl apply -f https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.15.1/manifest.yaml
kubectl -n cnpg-system rollout status deploy/barman-cloud
# or Helm:
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
helm upgrade --install plugin-barman-cloud --namespace cnpg-system cnpg/plugin-barman-cloud
kubectl -n cnpg-system rollout status deploy/plugin-barman-cloud
```
The manifest and Helm installs produce **different deployment names** (`barman-cloud` vs `plugin-barman-cloud`); check which one you got. Also `cmctl check api` for cert-manager.

### 6.2 Primary pod failure

**Percona:** No explicit procedure. The docs say Patroni does automated failover through a "leader race", and `cluster1-ha` follows the primary (`expose.md`).
- Implied behaviour: the leader key TTL is 30 s (`patroni.leaderLeaseDurationSeconds`) and loop_wait is 10 s, so expect failover within about 30 s of losing the leader. This is **not documented; derived from code defaults**.
- The role label changes `master` to `replica`. Check with:
  `kubectl get pods -l postgres-operator.crunchydata.com/cluster=cluster1 -L postgres-operator.crunchydata.com/role`
  or `kubectl exec <pod> -c database -- patronictl list`.
- If the former primary cannot rejoin (diverged timeline), `reinit.md` says Patroni may auto-reinit it. The manual option is `kubectl delete pvc/<inst>-pgdata pod/<inst>-0` or `patronictl reload` + `patronictl reinit`.

**CNPG:** `failover.md` / `failure_modes.md`.
- On readiness failure the operator marks TargetPrimary pending, shuts down the old primary (fast shutdown up to `switchoverDelay`, then immediate) and elects the most advanced replica. Promotion requires the `Lease`. `failoverDelay` defaults to 0.
- `-rw` repoints. The old primary is rewound with pg_rewind if its PVC is available, otherwise re-cloned.
- Check with `kubectl cnpg status cluster-example` and `kubectl get lease cluster-example`.
- Known issue: replicas may take about 127 s to reconnect; set `STANDBY_TCP_USER_TIMEOUT`.

### 6.3 Node failure
- **Percona:** `architecture.md` only says Kubernetes reschedules the pod on another node and Patroni handles the primary; anti-affinity is recommended (`constraints.md`). There is no timing, eviction or isolation guidance.
- **CNPG:** `failover.md` "Detection of node-level failures":
  - The primary is seen as unready about **40 to 55 s** after the node becomes unreachable (node-monitor-grace-period), then failover proceeds, gated by failoverDelay.
  - The isolated primary's liveness check fails within about 30 s, followed by a smart shutdown of up to 180 s (`smartShutdownTimeout`; set it to 0 to shorten the write window).
  - Pod eviction is governed by the 300 s `tolerationSeconds`. Full HA (recreation of the old primary) waits for that eviction.

### 6.4 Manual switchover
**Percona (`change-primary.md`):**
```bash
kubectl -n <ns> patch pg cluster1 --type=merge --patch '{"spec":{"patroni":{"switchover":{"enabled":true,"targetInstance":"cluster1-instance1-xxxx"}}}}'
kubectl annotate --overwrite -n <ns> pg cluster1 postgres-operator.crunchydata.com/trigger-switchover="$(date)"
# verify roles, then:
kubectl -n <ns> patch pg cluster1 --type=merge --patch '{"spec":{"patroni":{"switchover":{"enabled":false}}}}'
```
`targetInstance` is the instance name *without* the `-0` pod suffix, e.g. `cluster1-instance1-bmdp`.

**CNPG (`kubectl-plugin.md`):** `kubectl cnpg promote cluster-example cluster-example-2` (or the instance number: `kubectl cnpg promote cluster-example 2`).

### 6.5 Restore from backup
**Percona, in place (`backups-restore-inplace.md`):**
```yaml
apiVersion: pgv2.percona.com/v2
kind: PerconaPGRestore
metadata: {name: restore1}
spec:
  pgCluster: cluster1
  repoName: repo1
  # options: ["--type=immediate", "--set=20240628-074416F"]   # specific backup
```
Run `kubectl apply -f deploy/restore.yaml -n $NAMESPACE`. Find backup labels with `kubectl describe pg-backup <name>` (`Status.Backup Name`). It is destructive and invalidates logical replicas. To restore to a new cluster instead, use `spec.dataSource.pgbackrest` / `postgresCluster` / `volumes` in the new cluster's cr.yaml (`backups-clone.md`).

On-demand backup first: `kubectl apply -f deploy/backup.yaml -n <ns>`, then `kubectl get pg-backup backup1` and expect `Succeeded`.

**CNPG (`recovery.md`, plugin path):** create a new Cluster with:
```yaml
spec:
  bootstrap:
    recovery:
      source: origin
  externalClusters:
  - name: origin
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: cluster-example-backup
        serverName: cluster-example
```
Other sources: `bootstrap.recovery.backup.name: <Backup>` (from a Backup object) or `volumeSnapshots`. The backup must first exist: ObjectStore CR plus `.spec.plugins` on the source cluster, then `kubectl cnpg backup cluster-example` or a `Backup` CR with `method: plugin`. There is **no in-place option**.

### 6.6 PITR
**Percona (`backups-pitr-inplace.md`):**
```bash
kubectl get pg-backup <backup> -n $NAMESPACE -o jsonpath='{.status.latestRestorableTime}'
```
```yaml
spec:
  pgCluster: cluster1
  repoName: repo1
  options:
  - --type=time
  - --target="2025-11-30 15:12:11+03"
  # optional: - --set=<backupID from `pgbackrest --stanza=db info`>
```
The docs note that latestRestorableTime advances only when WAL with COMMITs is archived (archive_timeout 60 s). On an idle cluster, do a write and wait. A clone with PITR uses `dataSource.*.options` (`backups-pitr-cluster-clone.md`).

**CNPG:** a new cluster with `bootstrap.recovery.recoveryTarget.targetTime: "2023-08-11 11:14:21.00000+02"` (or targetLSN/targetXID/targetName/targetImmediate), plus an optional `backupID`. The operator picks the closest earlier backup.

### 6.7 Troubleshooting a stuck cluster
**Percona (`troubleshoot-operator.md`, `debug*.md`):**
1. `kubectl get pg` (expect `ready`; `initializing` while reconciling).
2. `kubectl describe pg <name>` (State / conditions; see `cr-statuses.md`).
3. `kubectl logs deploy/<operator-deployment>` (Deployment `percona-postgresql-operator` in bundle.yaml).
4. `kubectl get events --sort-by=.lastTimestamp`.
5. Check PVCs and PVs are Bound.
6. Look at the database and pgbouncer pod logs, with `-c` for containers (`database`, `pgbackrest`, `logs`, init container `postgres-startup`).
7. `kubectl exec ... -- patronictl list` (only shown in reinit.md).
8. If pods crash-loop, use the sleep-forever / probe-disable approach (`manage-manually.md`).
9. Use `spec.pause` for maintenance.
10. pprof profiling of the operator.
11. pgBackRest `--log-level-stderr=debug` in backup options.

**CNPG (`troubleshooting.md`):**
1. `kubectl cnpg status <cluster>` and `kubectl cnpg report cluster <cluster> --logs` (or `report operator`).
2. Check backups exist; take an emergency backup: `kubectl exec cluster-example-1 -c postgres -- pg_dump -Fc -d app > app.dump`.
3. `kubectl cnpg logs cluster <cluster> | kubectl cnpg logs pretty`.
4. Check cluster conditions (`kubectl wait --for=condition=Ready cluster/<name>`), storage, nodes and networking (NetworkPolicies to operator port 8000/webhook 9443).
5. Known stuck states: "Creating new replica" (network policy, `Instance Status Extraction Error: HTTP communication issue`), Pending pods, storage full, bootstrap init hang.
6. Emergency only: the `cnpg.io/reconciliationLoop: "disabled"` annotation; `kubectl cnpg maintenance` and fencing.
7. Barman plugin: `web/docs/troubleshooting.md` on the plugin site covers logs from the plugin manager and sidecar, backup, WAL archiving and restore failures, and object-store connectivity.

---

## 7. Unverified / open items
- Percona's per-version support lifecycle (only "2.8.x is EOL" is stated).
- Whether Percona backups run from replicas (repo-host architecture; not stated as such in the docs).
- Exact CNPG multi-arch platform list; CNPG VPA/HPA equivalent in Percona.
- EDB commercial TDE availability for CNPG-based images.
- (resolved) Percona operator Deployment name in bundle.yaml is `percona-postgresql-operator`.
- Crunchy Data's current corporate status (it affects the migration pitch).
