# Crunchy PGO vs Percona Operator for PostgreSQL 3.1.0: migration research

Desk research done on 2026-10-14. No servers were used. The sources were:

- the CRD YAMLs and Go code at the tags `CrunchyData/postgres-operator@v6.0.3` and `@v5.8.9`, `percona/percona-postgresql-operator@v3.1.0`, `CrunchyData/postgres-operator-examples@main`, and `percona/k8spg-docs@main` (commit of 2026-10-06);
- Crunchy and Percona documentation;
- the public Percona Jira REST API (`/rest/api/3/search/jql`);
- GitHub issues, Hacker News (Algolia API), and blogs.

Sources are listed at the end of each section. Inferences are marked **(inference)**, and statements I could not verify are marked **(unverified)**.

A hands-on colleague is testing in k3s. The places where lab verification matters most are marked **[LAB]**.

---

## 0. Executive summary

- **Crunchy Postgres for Kubernetes (CPK/PGO) has an announced end.** Crunchy sent subscription customers a *"Notice of Final Planned Releases"*. It says the final scheduled releases of CPK **5.6, 5.7, 5.8 and 6.0** will ship *"on or about December 31, 2026"*. After that, *"Crunchy Data does not plan to make available any additional releases … including future major releases."* Support continues only *"through the terms of their agreements."*
- Crunchy Data was **acquired by Snowflake**. The deal was announced on 2 June 2025 and closed on 6 June 2025, for $164.5M cash according to Snowflake's 10-K. Snowflake Postgres, built on Crunchy technology, went GA on 24 Feb 2026.
- **Latest versions.**
  - PGO **v6.0.3**: tagged 2026-08-17/20; no GitHub "release" object exists, the latest one is v6.0.2.
  - PGO **v5.8.9**: tagged in August 2026.
  - Percona **3.1.0**: released 2026-09-09. 3.0.0 came out on 2026-05-22 and was a hard fork with renamed CRDs.
- **Image licensing has not changed.** Crunchy images on `registry.developers.crunchydata.com` are governed by the *Crunchy Data Developer Program Terms*:
  - Production use is **not permitted for organizations with 50 or more employees** unless they hold an active Crunchy support subscription.
  - Redistribution is never permitted.
  - Use for consulting or support delivered to third parties is never permitted.

  The source code remains Apache-2.0. v6.0.0 added a `components/` directory, so users can **build their own images from PGDG packages**.
- **Percona documents three physical migration methods**: standby cluster via a shared pgBackRest repo, backup and restore, and reuse of the data PV. There is also a pre-migration checklist. All of these documents were tested against **Crunchy 5.8.x only**.
  - None of the documents mentions PGO v6 or the `v1` API.
  - None of them covers users and secrets, extensions, monitoring, pgAdmin, CR translation, or TLS continuity.
  - Percona's own Jira has an open documentation bug for these gaps (K8SPG-1197, fix version 3.2.0).
- **Biggest functional hazards found in the code:**
  1. The Percona operator runs `DROP EXTENSION IF EXISTS` in every database for each built-in extension whose `enabled` flag is false. Percona's defaults are false for `pg_stat_statements`, `pg_stat_monitor`, `pgvector`, `pg_repack`, `pg_cron` and `set_user`. A migrated Crunchy database that uses `pg_cron`, `pg_stat_statements` or `pg_repack` can therefore lose those extensions silently. Dropping `pg_cron` deletes the `cron.job` definitions. **[LAB]**
  2. `autoCreateUserSchema` defaults to **true** in Percona. In Crunchy it is opt-in by annotation. After migration, a schema named after each user appears in each of that user's databases, and new unqualified objects land there instead of in `public`.
  3. User Secrets are named after the cluster, and passwords are regenerated unless the Secrets are pre-seeded. Applications then lose credentials.
  4. Percona labels the primary pod `role=primary`; Crunchy labels it `role=master`. Custom selectors break.
  5. The Crunchy CA is shared per namespace (`pgo-root-cacert`). The Percona CA is per cluster (`<cluster>-cluster-ca-cert`). Clients using `verify-ca`/`verify-full` break unless the Crunchy CA is imported through `secrets.customRootCATLSSecret`.
  6. **PostGIS version regression**: Crunchy PG17/18 GIS images ship PostGIS 3.6, while Percona ships 3.5.7. A physical copy of a PostGIS 3.6 database onto 3.5 binaries is unsupported. **[LAB]**
  7. Extensions found only in Crunchy images: pg_partman, pg_jobmon, orafce, hypopg, pg_parquet, pgnodemx, TimescaleDB and pgrouting.
  8. Crunchy features with no Percona equivalent: pgMonitor exporter and dashboards, OTel instrumentation, and pgAdmin. Percona carries the PGAdmin CRD, but it has no controller (GitHub #1708).

---

## 1. Crunchy status and licensing

### 1.1 Corporate status

| Date | Event | Source |
|---|---|---|
| 2025-06-02 | Snowflake announces intent to acquire Crunchy Data at Snowflake Summit. Press reports put the price at about $250M. | Snowflake/BusinessWire press release; Crunchy blog "Crunchy Data Joins Snowflake" (Paul Laurence) |
| 2025-06-06 | Acquisition closes: "$164.5 million in cash, primarily for its talent and developed technology" | Snowflake FY2026 10-K, as quoted in search results and by layerbase.com |
| 2025-12 (approx.) | Crunchy sends subscription customers its **"Notice of Final Planned Releases"** (no date on the page; it schedules releases starting "end of February 2026") | info.crunchydata.com notice |
| 2025-12-08 | PGO v6.0.0 GitHub release | GitHub |
| 2025-12-12 | Percona blog repeats rumours that Crunchy Hardened PostgreSQL support ends around April 2026 (unconfirmed) | percona.com blog |
| 2026-02-24 | **Snowflake Postgres GA**, built on Crunchy technology. It is a separate product from Crunchy Bridge. | layerbase.com, pebbleit.com.au |
| 2026-08-25 | Crunchy Bridge is still sold. No sunset, rename or migration deadline announced for Bridge. | layerbase.com ("verified August 25, 2026") |
| ~2026-12-31 | **CPK "Final Release Date"** for 5.6, 5.7, 5.8 and 6.0 | Crunchy notice |

Text of the Crunchy notice (verbatim excerpts):

> "Crunchy Data is planning its final scheduled releases of Crunchy Postgres for Kubernetes 5.6, 5.7, 5.8, and 6.0 on or about December 31, 2026 (the "Final Release Date")."
>
> Minor releases are planned on or before the end of Feb, May, Aug and Nov 2026 (PostgreSQL 14–18), with "monthly rebuilds of Crunchy Postgres for Kubernetes containers up until the final release date".
>
> "Crunchy Data does not plan to make available any additional releases of Crunchy Postgres for Kubernetes, including future major releases of Crunchy Postgres for Kubernetes, after the Final Release Date."
>
> "with the release of Crunchy Postgres for Kubernetes 6.0.0, you can now build your own containers … using packages from the PGDG." The build files are in the `components` directory of the PGO GitHub repository.
>
> "Crunchy Data will continue to provide support to our customers … through the terms of their agreements."

The release cadence matches the notice:

| Release | Date | Notice commitment |
|---|---|---|
| 6.0.1 / 5.8.7 | 26 Feb 2026 | February |
| 6.0.2 / 5.8.8 | 2 Jun 2026 (installer commit 22 May) | May |
| 6.0.3 / 5.8.9 | Tag 17–20 Aug 2026 | August |

One more release is expected in **November 2026**, and then the line stops **(inference)**.

**Unverified claim:** pebbleit.com.au, a competitor marketing page, says "we have heard from a Crunchy customer that December 2026 is the deadline for Support". Treat this as unverified. The public notice talks only about releases, not support end.

**Licensing consequence (inference).** After the final release, organizations with 50 or more employees may still run Developer Program images in production only while they hold an active Crunchy support subscription. Two things make this a real risk:

- Crunchy has previously **removed images from the registry**. In March 2023, v4.x and older-PG images disappeared and production clusters broke (GitHub issue #3601, still open).
- The Developer Program only promises updates for "the latest two major versions".

Image availability after 2026 is therefore a real risk. Customers should mirror the images they use.

### 1.2 PGO release history (last ~24 months)

The public GitHub repo has **tags only for v5.7.9, v5.8.5–v5.8.9 and v6.0.0–v6.0.3**. Earlier v5 releases are not tagged in the repo. I inferred their dates from branch points and release commits, so they are approximate.

| Version | Date | Notes |
|---|---|---|
| 5.6.0 | ~Jun 2024 (commit "updated for the 5.6 release", 2024-06-11) | Last 5.6.x date not visible on GitHub |
| 5.7.0 | ~Oct 2024 (REL_5_7 branched 2024-09-30; "Post october 2024 release" commit) | PG17.0, Patroni 3.3.3, pgAdmin 4.30 and 8.12 |
| 5.7.4 | ~Mar 2025 | |
| 5.8.0 | ~Feb–Mar 2025 (REL_5_8 branched 2025-01-30) | **OTel logs/metrics (alpha gates)**, all images on **UBI 9**, Patroni 4.0.4, pgAdmin 9.1. Dropped PostGIS 3.0 and pgAdmin 4.30 on UBI 9. Warning about index rebuilds caused by the UBI 9 collation change. |
| (gap) | Mar–Nov 2025 | Bartolini notes an ~8-month release gap after the acquisition |
| 5.7.9 / 5.8.5 | 2025-11-24 | Adds PG 18 |
| **6.0.0** | **2025-12-08** | New `v1` API. See 1.3. |
| 5.8.6 | 2025-12-11 | |
| 6.0.1 / 5.8.7 | 2026-02-26 | PG 18.3. A 6.0.1 installer commit was reverted on 2026-02-17 and re-released later. |
| 6.0.2 / 5.8.8 | 2026-06-02 | PG 18.4, PostGIS 3.6.3, Patroni 4.1.3, pgBouncer 1.25.2, pgAdmin 9.15 |
| **6.0.3** / **5.8.9** | **2026-08-17/20** (tag only, no GitHub Release object) | PG 18.6/17.11/16.15/15.19/14.24, pgBackRest 2.59.0, Patroni 4.1.4, pgAdmin 9.17, OTel Collector 0.158/0.159, postgres_exporter 0.19.1. Fixes OTel metrics with custom ports and replication-slot query aliases. |

Repository activity after August 2026 consists of dependabot bumps only. There is one community fix PR (#4569) and one bug report (#4567, a `standby.signal` problem).

Repository stats on 2026-10-14:

| Repository | Stars | Forks | Open issues |
|---|---|---|---|
| Crunchy | 4.45k | 685 | 170 |
| Percona | 385 | 83 | 47 |

### 1.3 What changed in v6

Main sources: the 6.0.x release notes, and a diff I made of the v5.8.9 and v6.0.3 CRD schemas.

**API.** The `PostgresCluster` CRD now serves **`v1` and `v1beta1`**.

- **`v1beta1` remains the storage version.** `v1` is served with `storage: false`.
- The `v1` schema has the same fields as v6 `v1beta1`. It adds stricter CEL validation:
  - `userInterface` is rejected (`"userInterface not available in v1"`), so built-in pgAdmin 4.30 is gone in `v1`.
  - `instances` has `maxItems: 16`.
  - Log paths are restricted. `log_directory` must be under `/pgdata/logs/postgres`, `/pgtmp/logs/postgres`, `/pgwal/logs/postgres`, `/volumes…`, or `log`. pgBackRest and pgBouncer log paths must sit on declared additional volumes.
- `PGAdmin` and `PGUpgrade` remain `v1beta1` only.
- **The `CrunchyBridgeCluster` CRD was removed in v6.** It still existed in 5.8.

**Breaking changes, quoted from the release notes:**

- "maximum number of PgBouncer configuration settings … is 50"
- max 16 InstanceSets in `v1`
- "pgAdmin 4.30 no longer provisioned via v1 CRD"
- "The Postgres log directory is now outside the data directory by default". The default `log_directory` is now `/pgdata/logs/postgres`, with mandatory `log_file_mode=0660`.

**New fields in v6 compared with v5.8.9:**

- `instances[].volumes.additional`, which mounts extra PVCs or image volumes into any container;
- `instances[].dataVolumeClaimSpec.autoGrow` and `walVolumeClaimSpec.autoGrow`, auto-grow with thresholds;
- `backups.pgbackrest.log`, `.jobs.log/volumes`, `.repoHost.log/volumes`, `.restore.volumes`;
- `dataSource.*.volumes.additional`;
- `proxy.pgBouncer.volumes.additional`.

**Operator behaviour:**

- Pre-upgrade environment validation.
- The **AutoGrowVolumes** and **InstanceSidecars** feature gates are now on by default.
- The OpenTelemetryLogs and OpenTelemetryMetrics gates are still alpha and off by default.

**Monitoring stack location.** The kustomize monitoring stack (Prometheus, Grafana, Alertmanager) moved into `postgres-operator/config/monitoring`. `postgres-operator-examples` no longer has `kustomize/monitoring`. The examples now default to `apiVersion: postgres-operator.crunchydata.com/v1`, and the examples README says to change the version to `v1beta1` for PGO v5.

**Upgrade path from 5.x to 6.0.** Re-apply the installer (`kubectl apply --server-side -k config/default`). v5.0.x and older need extra steps. The docs warn that operator upgrades "may automatically rollout changes to managed Postgres clusters".

### 1.4 Images, registry and install methods

**Default images (v6.0.3 `config/components/images-by-tag`)** are all under `registry.developers.crunchydata.com/crunchydata/…`:

| Image | v6.0.3 tag |
|---|---|
| `postgres-operator` | `ubi9-6.0.3-0` (5.8: `ubi9-5.8.9-0`) |
| `crunchy-postgres` | `ubi9-18.6-2633` (15/16/17 similar) |
| `crunchy-postgres-gis` | `ubi9-18.6-3.6-2633`. PG17 has PostGIS 3.4, 3.5 and 3.6; PG16 has 3.3 and 3.4. |
| `crunchy-pgbackrest` | `ubi9-2.59.0` |
| `crunchy-pgbouncer` | `ubi9-1.25` |
| `crunchy-postgres-exporter` | `ubi9-0.19.1` |
| `crunchy-pgadmin4` | `ubi9-9.17` |
| `crunchy-upgrade` | `ubi9-18.6` |

The default kustomization contains no PG14 image, although PG14 is listed as supported.

**Extensions in Crunchy images (CPK 6.0.3 components page):**

- hypopg 1.4.2
- orafce 4.16.5
- pgAudit
- pg_cron 1.6.7
- pg_jobmon 1.4.1
- pg_parquet 0.5.1
- pg_partman 5.5.0
- pgnodemx 1.7
- pgvector 0.8.0
- set_user 4.2.0
- TimescaleDB 2.29.1 (PG16–18)
- wal2json 2.6
- GIS image only: PostGIS 3.6 and pgrouting 3.7.1

**Image terms (Crunchy Developer Program Terms of Use, fetched 2026-10-14; no Snowflake changes visible):**

| Use | Fewer than 50 employees | 50 or more employees |
|---|---|---|
| Development use | Permitted | Permitted |
| Production use | Permitted | **Not permitted** without an active Crunchy support subscription ("deemed a violation") |
| Resale or redistribution | Not permitted | Not permitted |
| Consulting or support services delivered to third parties | Not permitted | Not permitted |

- "Production Purposes" includes "backup instances".
- The program promises updates only for "the latest two major versions of Crunchy Postgres for Kubernetes and PostgreSQL".

**Install methods:**

| Method | How |
|---|---|
| Kustomize | `kubectl apply --server-side -k config/default` from the `postgres-operator` repo. Cluster-wide by default; `config/singlenamespace` for one namespace. |
| Helm (operator) | OCI chart: `helm install pgo oci://registry.developers.crunchydata.com/crunchydata/pgo`. `singleNamespace`, `PGO_TARGET_NAMESPACES` via `extraEnv`, `controllerImages`. Helm leaves CRDs in place on uninstall. |
| Helm (cluster) | Example chart `postgres-operator-examples/helm/postgres` (`postgrescluster` chart 6.0.0). Minimal. |
| OLM / OperatorHub | Community `postgresql` package and Red Hat certified listing |
| CLI | `kubectl pgo` plugin (CrunchyData/postgres-operator-client v0.5.3, 2025-10-01), used for support exports, backups and so on |

**Supported platforms (Crunchy docs):**

| Line | Kubernetes | OpenShift | PostgreSQL | Status |
|---|---|---|---|---|
| CPK 6.0.x | 1.32–1.36 | 4.16–4.22 | 14–18 | Active / Developer |
| CPK 5.8.x | 1.30–1.36 | 4.14–4.22 | 14–18 | Active / Developer |

Policy text: Crunchy "will generally maintain the current and two past versions as Active"; "Extended" support requires an Extended subscription.

### 1.5 Community sentiment

- **HN.** In 2022–2023 there were repeated complaints that PGO cannot be used in production without a subscription (threads 31882256 and 34750934). In 2026 comments focus on the Snowflake purchase being about pg_lake and data lakes. One commenter (2026-05) described replacing Crunchy with CloudNativePG (CNPG). Gabriele Bartolini's post "CloudNativePG and Crunchy PGO: an honest, opinionated comparison" (2026-05) reached HN.
- **Bartolini (EDB/CNPG, biased).** He cites the Developer Program 50-employee restriction, the ~8-month release gap, the Snowflake acquisition, and "the absence of public governance" as what teams "most frequently raise".
- **Vendor content.** Percona ("Not All Open Source Is Equal… 2026", the migration-methods blog, the Hardened PG EOL blog), pebbleit (PostgresPURE), layerbase, chat2db and simplyblock all position "Crunchy CPK EOL Dec 31 2026" as a forcing event. **chat2db and others recommend CNPG as the default replacement.** Percona is framed as the "hard fork" option with the most familiar operating model.
- **SAS.** SAS Communities has a thread "Crunchy Postgres for Kubernetes Support at End-of-Life" (Viya bundles CPK). The page returned HTTP 403, so its content is unverified, but the title confirms that downstream ISVs are affected.
- **Percona maintainers.** In percona-postgresql-operator #1708 (2026-07/08) a maintainer wrote: "With Crunchy going EOL and migrations happening, people started to ask about pgAdmin." In #1687 a user wrote: "so far the migrations from crunchy to this operator have been going well".
- **Reddit** search API was blocked from this environment. No Reddit data was collected.

**Sources for section 1**

- https://info.crunchydata.com/crunchy-postgres-for-kubernetes-notice-of-final-planned-releases
- https://www.crunchydata.com/developers/terms-of-use
- https://www.businesswire.com/news/home/20250602455530/en/Snowflake-Acquires-Crunchy-Data-to-Bring-Enterprise-Ready-Postgres-Offering-to-the-AI-Data-Cloud
- https://www.crunchydata.com/blog/crunchy-data-joins-snowflake
- https://layerbase.com/blog/crunchy-bridge-alternative
- https://www.pebbleit.com.au/insight/crunchy-postgresql-v-postgrespure
- https://access.crunchydata.com/documentation/postgres-operator/6.0/releases/6.0.x
- https://access.crunchydata.com/documentation/postgres-operator/latest/releases/5.8.x
- https://access.crunchydata.com/documentation/postgres-operator/latest/overview/supported-platforms
- https://access.crunchydata.com/documentation/postgres-operator/latest/installation/helm
- https://access.crunchydata.com/documentation/postgres-operator/latest/upgrade/kustomize
- https://access.crunchydata.com/documentation/postgres-operator/latest/references/components
- https://github.com/CrunchyData/postgres-operator/issues/3601
- https://github.com/CrunchyData/postgres-operator-examples (README)
- https://www.gabrielebartolini.it/articles/2026/05/cloudnativepg-and-crunchy-pgo-an-honest-opinionated-comparison/
- https://www.percona.com/blog/support-for-crunchy-hardened-postgresql-ends-soon-dont-get-caught-off-guard/
- https://communities.sas.com/t5/Administration-and-Deployment/Crunchy-Postgres-for-Kubernetes-Support-at-End-of-Life/td-p/984555
- https://news.ycombinator.com/item?id=31882256 , https://news.ycombinator.com/item?id=34750934 , https://news.ycombinator.com/item?id=48248201

---

## 2. Feature and CRD mapping: PGO v6.0.3 PostgresCluster to Percona 3.1.0 PerconaPGCluster

**How the CRDs map.**

- **Crunchy:** `postgres-operator.crunchydata.com/{v1,v1beta1}` PostgresCluster.
- **Percona:** the user-facing `pgv2.percona.com/v2` PerconaPGCluster. The operator renders an inner `upstream.pgv2.percona.com/v1beta1` PostgresCluster from it. Since 3.0.0 the upstream CRDs were renamed to the `upstream.pgv2.percona.com` group.
- **Percona's inner upstream schema has no `instrumentation` field.** The fork predates Crunchy 5.8's OTel work, or did not merge it **(inference)**.

**How the comparison was made.** I generated a set-difference of all field paths to depth 3, which is the basis of the table below.

**Migration impact legend:**

| Term | Meaning |
|---|---|
| none | Same field and semantics; copy as-is |
| translate | Equivalent feature with a different field or shape; mechanical conversion |
| manual | Needs human design or extra objects |
| gap | No equivalent in Percona 3.1 |

| Feature | Crunchy PGO v6.0.3 (v5.8 differences) | Percona 3.1.0 | Impact |
|---|---|---|---|
| API / kind | `PostgresCluster` `v1` (served) and `v1beta1` (storage). v5.8 has `v1beta1` only. | `PerconaPGCluster` `pgv2.percona.com/v2` plus required `crVersion` | translate |
| PG version | `postgresVersion` (14–18) | `postgresVersion` (14–18; 19 tech preview with community images) | none |
| Image | `image` optional; the operator picks `RELATED_IMAGE_POSTGRES_<v>[_GIS_<x>]` | `image` effectively required (set in cr.yaml); UBI 8/9/10 variants; community PGDG images | translate (choose image) |
| PostGIS | `postGISVersion` picks the GIS image; PostGIS 3.6 on PG17/18 | No field; use the `percona-distribution-postgresql:<v>-postgis` image. **PostGIS 3.5.7 only.** | translate / **gap for PostGIS 3.6** |
| imagePullPolicy / imagePullSecrets | Yes | Yes | none |
| Instances | `instances[]`: name, replicas, resources, affinity, tolerations, topologySpreadConstraints, priorityClassName, minAvailable, metadata, dataVolumeClaimSpec, walVolumeClaimSpec, tablespaceVolumes | Same core fields, plus env/envFrom, securityContext, initContainers, sidecars, sidecarVolumes/PVCs, extraVolumes, volumeMounts | none for the core fields |
| Instance sidecars | `instances[].containers` (InstanceSidecars gate, **default on in v6**) | `instances[].sidecars` (gate on the inner layer; Percona exposes it as a field) | translate |
| Extra volumes | v6 `instances[].volumes.additional` (PVC or image volume per container), `volumes.temp` (`/pgtmp`) | `instances[].extraVolumes` (3.1.0, any volumeSource, mounted into the database container), `sidecarVolumes`, `sidecarPVCs` | translate; `volumes.temp` is a **gap** |
| Auto-grow storage | v6 `dataVolumeClaimSpec.autoGrow` (thresholds) plus `resources.limits.storage`; AutoGrowVolumes gate **default true** | `resources.limits.storage` with the `AutoGrowVolumes` gate **default false**; 3.1.0 also covers repo-host volumes | translate (enable the gate; thresholds are lost) |
| Tablespaces | `tablespaceVolumes` (TablespaceVolumes gate) | Same | none (gate) |
| Users | `users[]`: name, databases, options, password.type | Same, plus `secretName` and `grantPublicSchemaAccess`. `monitor` and `logicalrepl` are reserved. | none, but see 3.4 on secrets |
| Auto user schema | Annotation `postgres-operator.crunchydata.com/autoCreateUserSchema: "true"` (opt-in) | `spec.autoCreateUserSchema`, **default true** | **behaviour change**; set it to false to keep Crunchy behaviour |
| databaseInitSQL | ConfigMap name and key | Same | none |
| Authentication / LDAP | `authentication.rules[]` (hba, connection, method, options, users, databases) | Same field. LDAP bind password stored as plain text (K8SPG-968 open). | none |
| PG config | `config.parameters`, `config.files` (projected volumes) | Same | none |
| Patroni | `patroni.dynamicConfiguration`, `switchover{enabled, targetInstance, type}`, `leaderLeaseDurationSeconds`, `syncPeriodSeconds`, `port`, v5.8+ `patroni.logging{level, storageLimit}` | Same, minus `logging`, plus `createReplicaMethods` and `removeDataDirectoryOnDivergedTimelines` | none; `patroni.logging` is a gap |
| Switchover trigger | Annotation `postgres-operator.crunchydata.com/trigger-switchover` | Same mechanism on PerconaPGCluster (see Percona change-primary doc) | none / translate |
| Backups: pgBackRest repos | `backups.pgbackrest.repos[]` (volume, s3, gcs, azure), `global`, `configuration`, `repoHost`, `jobs`, `sidecars`, `metadata`, `image`, v6 `log` | Same, plus `containers`, env/envFrom, initContainer, `jobs.backoffLimit`/`restartPolicy`, repoHost sidecars; no v6 `log`/`volumes` | none (drop v6 log fields) |
| Backup on/off | Backups optional since 5.7 (omit `backups`) | `backups.enabled: false` | translate |
| Schedules | `repos[].schedules{full, differential, incremental}` run as **CronJobs** | Same fields, but Percona strips them from the inner cluster and runs an in-process scheduler that creates `PerconaPGBackup` objects | translate. Do not write schedules into the inner object: duplicate backups, GitHub #1731. |
| Manual backup | `backups.pgbackrest.manual` plus annotation `pgbackrest-backup` | `PerconaPGBackup` CR (`repoName`, `options`) | translate |
| Restore (in place) | `backups.pgbackrest.restore` plus annotation `pgbackrest-restore` | `PerconaPGRestore` CR | translate |
| Retention | `global.repoN-retention-full` and so on | Same | none |
| Volume-snapshot backups | `backups.snapshots.volumeSnapshotClassName` (VolumeSnapshots gate, alpha) | `backups.volumeSnapshots{className, mode, schedule, offlineConfig, jobs}` (BackupSnapshots gate, tech preview) | translate |
| `trackLatestRestorableTime` | N/A | Percona only | n/a |
| dataSource | `pgbackrest` (stanza, repo, global, configuration, options), `postgresCluster` (clusterName, clusterNamespace, repoName, options), `volumes` (pgDataVolume, pgWALVolume, pgBackRestVolume); v6 adds `volumes.additional` | Same three variants; 3.1 lets `dataSource.volumes` work without `repoName` (K8SPG-1119) | none. Note `postgresCluster` refers to a **Percona** cluster, so it is not usable across operators. |
| Standby | `standby{enabled, host, port, repoName}` | Same plus `maxAcceptableLag`. Removing the `standby` block does not promote (K8SPG-1099 open); set `enabled: false`. | none |
| pgBouncer | `proxy.pgBouncer`: replicas, config (max 50 settings in v6), customTLSSecret, image, port, service, sidecars, containers, v6 volumes, affinity and so on | Same, plus `expose` (in place of `service`), `exposeSuperusers`, `paused` (3.1), `usersSecret`, `additionalTrustedCAs` (3.1), env, securityContext | translate (`service` becomes `expose`) |
| Services | `service`, `replicaService` (type, nodePort, metadata, externalTrafficPolicy, internalTrafficPolicy, ipFamilies, ipFamilyPolicy) | `expose`, `exposeReplicas` (type, nodePort, annotations, labels, loadBalancerClass, loadBalancerSourceRanges); no trafficPolicy or ipFamily | translate / partial gap |
| TLS | `customTLSSecret`, `customReplicationTLSSecret` (top level); namespace CA `pgo-root-cacert` | `secrets.customTLSSecret`, `secrets.customReplicationTLSSecret`, `secrets.customRootCATLSSecret`; `tls{certManagementPolicy, issuerConf (cert-manager), validity}`; `tlsOnly` | translate; CA continuity is manual (see 3.6) |
| Monitoring | `monitoring.pgmonitor.exporter` (crunchy-postgres-exporter sidecar, `ccp_monitoring` user, pgMonitor queries, pgnodemx) plus the kustomize Prometheus/Grafana/Alertmanager stack | `pmm` (PMM3 client sidecar; PMM2 removed in 3.1). Or a manual `postgres_exporter` sidecar (doc page; the operator does not manage it). | **gap / manual** |
| OpenTelemetry | `instrumentation{config, image, logs, metrics, resources}` (5.8+; gates OpenTelemetryLogs/Metrics) | No `instrumentation`. `logcollector` (Fluent Bit, 3.1.0) can forward logs to OTel or S3. No OTel metrics. | **gap** (logs: manual via Fluent Bit) |
| Log handling | v6 logs outside PGDATA (`/pgdata/logs/postgres`), PVC log targets | Default `log` inside PGDATA; persistent logs plus rotation via `logcollector` | translate |
| pgAdmin (embedded) | `userInterface.pgAdmin` (v1beta1 only, pgAdmin 4.30, deprecated; rejected in v1) | None | **gap** |
| pgAdmin (standalone) | `PGAdmin` CRD v1beta1 (pgAdmin 9.x, server groups, OAuth2/LDAP) | CRD present under `upstream.pgv2.percona.com` but **no controller** (GitHub #1708, K8SPG-1110/1129 open) | **gap** |
| Major upgrade | `PGUpgrade` CRD (fromPostgresVersion, toPostgresVersion, image, `transferMethod`, `jobs`) plus annotation `postgres-operator.crunchydata.com/allow-upgrade` and `shutdown: true` | `PerconaPGUpgrade` pgv2.percona.com/v2 (from/to version, toPostgresImage, toPgBouncerImage, toPgBackRestImage); no transferMethod | translate |
| CrunchyBridgeCluster | Removed in v6 (present in 5.8) | Inherited CRD still installed (`upstream.pgv2.percona.com`), unused | n/a |
| Shutdown | `shutdown: true` | `pause: true` (maps to inner `shutdown`) | translate |
| Pause reconcile | `paused: true` | `unmanaged: true` | translate |
| `disableDefaultPodScheduling` | Yes | No | gap (minor) |
| `supplementalGroups` | Top level | `instances[].securityContext.supplementalGroups` | translate |
| `openshift` | Auto-detected or field | Field exists | none |
| `port` | Yes | Yes | none |
| `metadata` (labels/annotations for all objects) | Yes | Yes | none |
| Extensions management | None. pgAudit is always preloaded and created. pgMonitor creates pg_stat_statements in all DBs and pgnodemx. Everything else is up to the user (all extensions are in the image). | `extensions.{pg_audit (default true), pg_stat_statements, pg_stat_monitor, pgvector, pg_repack, pg_cron, set_user, pg_tde}.enabled`; `extensions.custom[]` downloaded from S3 | **manual. Hazard: disabled built-ins are DROPPED** (section 3.3). |
| TDE | No TDE in CPK. Crunchy's TDE existed only in Crunchy Hardened PostgreSQL (non-K8s); the K8s guidance is encrypted StorageClasses. | `extensions.pg_tde` with Vault KV v2 (PG17/18, Percona images only) | n/a (Percona-only upside) |
| pg_partman / pg_jobmon / orafce / hypopg / pg_parquet / TimescaleDB / pgnodemx / pgrouting | In image | **Not in the Percona image.** Needs `extensions.custom` tarballs or a custom image. | **gap** |
| pg_cron / set_user / pgvector / pg_repack / wal2json / pgaudit | In image | In image (pg_cron and set_user built-in since 3.1) | none (but enable them explicitly) |
| Logical replicas | N/A | `logicalReplicas[]` (3.1 tech preview) | n/a |
| Telemetry | Crunchy upgrade-check telemetry | Percona telemetry (platform reported since 3.1) | n/a |

**Sources for section 2**

- `config/crd/bases/*.yaml` at the three tags
- `internal/feature/features.go`
- `percona/.../perconapgcluster_types.go`
- https://access.crunchydata.com/documentation/postgres-operator/latest/references/components
- Percona RN 3.0.0 and 3.1.0 (k8spg-docs `docs/ReleaseNotes`)
- https://github.com/percona/percona-postgresql-operator/issues/1708 , /1731 , /1687
- https://perconadev.atlassian.net/browse/K8SPG-1099

---

## 3. Behavioural differences that matter operationally

These were checked in the code at the stated tags.

### 3.1 Labels and annotations

- **Label prefix.** Percona still uses the Crunchy prefix `postgres-operator.crunchydata.com/` for all cluster, instance, role, data, pgbackrest and pgbouncer labels and annotations (`internal/naming/labels.go`). It adds `pgv2.percona.com/version` and `app.kubernetes.io/{name, instance, component, managed-by=percona-postgresql-operator, part-of}`.
  - Existing selectors, NetworkPolicies, PodMonitors and scripts that use `postgres-operator.crunchydata.com/cluster=<name>` keep working.
  - **The exception is the primary role.**
- **Primary role label:**
  - Crunchy: `RolePatroniLeader = "master"`, so the primary pod has `postgres-operator.crunchydata.com/role=master`.
  - Percona: `RolePatroniLeader = "primary"` (`"master"` deprecated, K8SPG-648, Patroni 4).
  - Anything selecting `role=master` (custom Services, PodMonitors, alert rules, runbooks, Percona's own migration docs when used on the Percona side) must change. The Operator-created Services in both use the `<cluster>-primary` Endpoints, which the operator manages, so they keep working.
- **Coexistence.** CRD groups differ, so both operators can run in one Kubernetes cluster (Percona 3.0 goal, K8SPG-1016).
  - Because labels **and** resource naming are identical, **two clusters with the same name in the same namespace would collide.** They would share Services, Secrets, and the Patroni `<name>-ha-config`/`-leader` objects.
  - Percona docs use different names and namespaces but never warn about this **(inference; [LAB] do not test on production)**.
- **Annotations.**
  - Crunchy v6 adds `pgbackrest-config` and `pgbackrest-cloud-log-volume`.
  - Percona adds `adopt-bridge-cluster` and `suggested-pgbackrest-*`.
  - Trigger annotations (`pgbackrest-backup`, `pgbackrest-restore`, `trigger-switchover`) have the same names. In Percona the supported interface is the PerconaPGBackup and PerconaPGRestore CRs.

### 3.2 Names of Services, Secrets and other objects

Names are identical except as noted:

- **Services:** `<cluster>-primary`, `-replicas`, `-ha`, `-ha-config`, `-pods`, `-pgbouncer`
- **Secrets:** `<cluster>-pguser-<user>`, `<cluster>-pgbouncer`, `<cluster>-pgbackrest`, `<cluster>-cluster-cert`, `<cluster>-replication-cert`, `<instance>-certs`, `<cluster>-monitoring`
- **PVCs:** `<instance>-pgdata`, `-pgwal`, `<cluster>-repo1`

Differences:

- Percona adds `<cluster>-cluster-ca-cert`, `<cluster>-pgbackrest-{client,repo}-tls`, and cert-manager issuers `<cluster>-ca-issuer`/`-tls-issuer`.
- Crunchy has `<cluster>-repohost` (RBAC for the repo host).

**User Secret keys are identical:** `user`, `password`, `verifier`, `dbname`, `host`, `port`, `uri`, `jdbc-uri`, `pgbouncer-host`, `pgbouncer-port`, `pgbouncer-uri`, `pgbouncer-jdbc-uri`.

**Consequence.** If the Percona cluster keeps the **same cluster name**, application connection strings and Secret names survive. Percona's three guides all rename the cluster (`crunchy-source` becomes `cluster1`).

### 3.3 Extensions (most dangerous difference)

**Crunchy:**

- Always preloads and creates `pgaudit` in all databases.
- With monitoring enabled, preloads `pg_stat_statements` and `pgnodemx`, creates `pg_stat_statements` in **all** databases, and creates `pgnodemx` in schema `monitor` of the postgres database (`internal/pgmonitor/postgres.go`).
- Leaves all other extensions untouched.

**Percona** (`internal/controller/postgrescluster/postgres.go` lines ~309–410 and `perconapgcluster_types.go` defaults):

- On every Postgres reconcile, for each built-in, it runs `CREATE EXTENSION` if enabled and **`DROP EXTENSION IF EXISTS <ext>` (no CASCADE) in all databases if disabled**.
- Defaults: `pg_audit=true`; `pg_stat_statements=false` (true only if PMM with querySource pgstatstatements); `pg_stat_monitor=false`; `pgvector=false`; `pg_repack=false`; `pg_cron=false` (unless listed in `extensions.custom`); `set_user=false`.
- Custom extensions removed from `extensions.custom` are also dropped.

Consequences after a physical migration with a default CR **(inference from code; [LAB] verify)**:

| Extension | Expected outcome |
|---|---|
| `pg_cron` | Dropped. **Its `cron.job` table and job definitions are deleted.** |
| `pg_repack`, `set_user`, `pg_stat_monitor` | Dropped |
| `pg_stat_statements` | Dropped. If pgMonitor views depend on it, the DROP fails and the operator keeps emitting warning events. |
| `pgvector` with vector columns | DROP fails (no CASCADE), with warning events every reconcile. Confirmed in K8SPG-1197. |
| `pgnodemx`, `pg_partman`, `pg_jobmon`, `orafce`, `hypopg`, `timescaledb`, `pg_parquet`, `pgrouting`, PostGIS 3.6 | Catalog entries survive but `.so` files are missing, so calls fail. If `shared_preload_libraries` in a copied `dynamicConfiguration` lists `timescaledb` or `pgnodemx`, **PostgreSQL will not start**. |

Extension versions can also differ, for example pgvector or pg_cron versions. K8SPG-1197 notes that the operator may run `ALTER EXTENSION … UPDATE`; Percona's built-in "enable" functions do so.

### 3.4 Users, passwords and Secrets

- **The reconcile model is the same.** The Secret for each `spec.users` entry is created if missing, with a generated password, and the role is then `ALTER ROLE … PASSWORD <verifier>`.
- **Effect on a renamed cluster.** A physically migrated database keeps its roles. If the Percona cluster has a different name, or the Secrets are not pre-created, the operator **generates new passwords and overwrites them in the database**. Applications that still use the Crunchy Secret values break.
- **How to keep passwords (inference):** pre-create `<newcluster>-pguser-<user>` with `password` and `verifier` copied from the Crunchy Secret, plus the labels `postgres-operator.crunchydata.com/cluster` and `postgres-operator.crunchydata.com/pguser`. Alternatively, use `users[].secretName`. **[LAB]**
- **Default user.** With no `spec.users`, both operators create a user and database named after the cluster. A renamed cluster therefore gets a new, empty database (for example `cluster1`).
- **Monitoring user.**
  - Crunchy uses `ccp_monitoring` (Secret `<cluster>-monitoring`), with hba restricted to localhost. Percona keeps the ccp_monitoring code path for the inner exporter, which is unused.
  - **PMM uses user `monitor` with SUPERUSER** (Secret `<cluster>-pguser-monitor`).
  - Leftover `ccp_monitoring` and the `monitor` schema objects stay in a migrated database.
- **Internal users** are the same: `_crunchyrepl` (replication, cert auth) and `_crunchypgbouncer`. Percona adds `_crunchypgbounceradmin` (3.1 pause/resume) and `logicalrepl`.

### 3.5 Images and defaults

| Area | Crunchy | Percona |
|---|---|---|
| Postgres image | UBI 9 (since 5.8). 5.7 and earlier ran UBI 8, so the collation change matters for older clusters. | `percona-distribution-postgresql` UBI 9 by default; `-ubi8` and `-ubi10` variants were added in 3.1 to match source OS/glibc |
| pgBackRest | 2.59.0 | 2.59.1 |
| Patroni | 4.1.4 | 4.1.5 |
| Default `wal_level` | Mandatory `logical` | Default `logical`, overridable |
| Default `log_directory` (v6) | `/pgdata/logs/postgres` | `log` |
| Other PG defaults | `ssl=on`, `password_encryption=scram-sha-256`, `jit=off` | Same |
| `pg_stat_statements.track` | — | Percona forces `all` when the extension is enabled (K8SPG-1198 open) |
| pgBouncer | Only if `proxy.pgBouncer` is set; same config generator | `deploy/cr.yaml` enables 3 pgBouncer replicas; `exposeSuperusers: false` |
| Default cluster shape | Defined by the user's CR | `deploy/cr.yaml`: 3 instances, 3 pgBouncer, repo1 volume |

### 3.6 TLS and CA

| Area | Crunchy | Percona |
|---|---|---|
| Root CA | Operator-managed root CA stored in **`pgo-root-cacert`** in each namespace (keys `root.crt`/`root.key`, 10-year life), shared by all clusters | **Per-cluster** `<cluster>-cluster-ca-cert` (K8SPG-555). Optional cert-manager or custom issuer (`tls.issuerConf`, 3.1). `tls.certManagementPolicy` (3.1). |
| Leaf certificates | 1-year life, auto-rotated by the operator | Operator-managed |
| `pgo-root-cacert` | Active | Constant kept only for upgrades from ≤2.4 |

**Client continuity.** `secrets.customRootCATLSSecret` expects `root.crt`/`root.key`, which is exactly the format of `pgo-root-cacert`. So the Crunchy CA can be imported to keep clients with `verify-ca`/`verify-full` working **(inference; [LAB])**. Percona docs do not mention this.

**The standby guide reuses Crunchy certificates.** It copies Crunchy's `<cluster>-cluster-cert` and `-replication-cert` into Percona `secrets.customTLSSecret`/`customReplicationTLSSecret` and never replaces them:

- The certificates were issued for **Crunchy hostnames** (`crunchy-source-primary…`).
- They expire **one year** after Crunchy issued them.
- Percona cannot renew them without the Crunchy CA key.

A post-cutover certificate migration step is missing.

### 3.7 pgBackRest repository format

- Default repo path `/pgbackrest/repo1` and stanza **`db`** are identical (`DefaultStanzaName = "db"`). A Crunchy repo can be read by Percona directly, as the standby and restore guides rely on.
- Crunchy schedules run as CronJobs; Percona schedules run in-process and create PerconaPGBackup objects (see section 2).
- Bug GitHub #1731: if schedules end up in the inner PostgresCluster, backups run twice and race for the lock.

### 3.8 Namespace scope, install and OpenShift

| Area | Crunchy | Percona |
|---|---|---|
| Default install scope | **Cluster-wide** (kustomize default and Helm default) | **Namespace-scoped**: `deploy/bundle.yaml`; cluster-wide via `cw-bundle.yaml` with `WATCH_NAMESPACE` |
| Helm | OCI `pgo` | `percona/pg-operator` and `percona/pg-db` charts; K8SPG-926 notes missing sane defaults in `pg-db` |
| OLM | Community `postgresql` package; Red Hat certified listing | Community package (3.0 fixed OperatorGroup scoping) and certified listing |
| OpenShift | v6: 4.16–4.22; monitoring kustomize needs `fsGroup` removed | Tested on 4.19–4.22. 3.1 made the PMM sidecar work with `readOnlyRootFilesystem` (restricted-v2). |
| Kubernetes tested | CPK 6.0: 1.32–1.36 | Percona 3.1: GKE 1.34–1.35, EKS/AKS/RKE2 1.34–1.36, Minikube 1.35 |

### 3.9 Tooling

- Crunchy has the `kubectl pgo` plugin, used for backups, `support export`, `start`/`stop` and similar. Percona has no equivalent plugin.
- Crunchy ships pgMonitor Grafana dashboards (`ccp_*` metrics). PMM dashboards use different metric names, so existing Crunchy alerting and dashboards do not carry over.

---

## 4. Percona's documented migration paths from Crunchy

**Pages** (k8spg-docs `main`; published under `/latest/`, `/3.1.0/` and `/3.0.0/`):

- `migrate-from-crunchy.md`: overview and comparison table
- `migrate-checklist.md`: pre-migration compatibility checks. Added after K8SPG-1143 ("Data corruption risk at documentation", Done, 3.1.0).
- `migrate-from-crunchy-standby.md`
- `migrate-from-crunchy-backup-restore.md`
- `migrate-from-crunchy-data-volumes.md`

**Related material:**

- Percona blog "Comparing Migration Methods…" (Chetan Shivashankar, 2026-07-07). It lists four methods, including `pg_basebackup` streaming replication, which has no docs page.
- RN 3.0.0: "Crunchy CRD renaming… Safe coexistence of Percona Operator for PostgreSQL and Crunchy PGO".

**Shared prerequisites.** All three guides include the snippet *"Versions used in this guide: Crunchy PostgreSQL Operator 5.8.x; Percona Operator 3.x.x; AWS S3"*. Crunchy install links point to `…/postgres-operator/5.8/quickstart`, and all Crunchy manifests use `v1beta1`. **There is no mention of PGO 6.0, the `v1` API, 5.6/5.7, or v4.** The checklist requires the same PG major and CPU architecture, and treats glibc and ICU differences as needing REINDEX and `REFRESH COLLATION VERSION`. It also asks for "at least three successful trial runs".

### 4.1 Method A: standby cluster via shared pgBackRest repo plus streaming

**Steps:**

1. Configure the Crunchy pgBackRest repo1 on S3, with a path shared by both clusters (`repo1-path: /crunchy-to-percona/repo1`). Expose the Crunchy cluster.
2. Take a full backup with the `pgbackrest-backup` annotation.
3. Copy `<crunchy>-cluster-cert` and `-replication-cert` to the Percona namespace.
4. Install the Percona operator.
5. Create the `PerconaPGCluster` with:
   - `standby{enabled: true, host: crunchy-source-ha.<ns>.svc.cluster.local, port: 5432, repoName: repo1}`;
   - `secrets.customTLSSecret` and `customReplicationTLSSecret` set to the Crunchy certificates;
   - an identical repo1 configuration.

   The cluster restores from S3, replays WAL, and then streams.
6. Check lag on the Crunchy primary (`role=master`).
7. Cutover: patch Crunchy to `standby.enabled=true, repoName=repo1`. Optionally set `shutdown: true`.
8. Wait until the Percona replay LSN stops moving, then patch Percona `standby.enabled=false`.
9. Wait for `stanzaCreated`, take a post-migration backup, and repoint applications to `cluster1-pgbouncer`.
10. Rollback is possible until the post-migration backup.

**Characteristics:**

- **Downtime:** the cutover window only.
- **Prerequisites:** remote object storage reachable from both clusters; network from the Percona pods to the Crunchy `-ha` Service; same PG major and architecture.

**Gaps and errors:**

- Numbering in "Make a full backup" starts at **2.**
- `kubectl wait job -l A -l B` repeats `-l`; kubectl uses only the last selector.
- The post-migration backup tells you to edit `deploy/backup.yaml` but then runs `kubectl apply -f deploy/post-migration-backup.yaml`, which doesn't exist.
- TLS: Crunchy-issued certificates stay on the Percona cluster permanently (wrong SANs, one-year expiry, not renewable). No step moves to Percona-managed TLS or imports `pgo-root-cacert` as `customRootCATLSSecret`.
- Both clusters write to **the same repo path**. After promotion, Percona retention will expire Crunchy-era backups, and the doc does not say so. Leaving Crunchy running in standby on the same repo is "optional" to shut down.
- Only S3 is shown. The default Crunchy repo is a PVC (`repo1.volume`) and is not covered.
- Users and Secrets are not addressed: new Secret names, regenerated passwords. Neither are extensions (DROP risk), `autoCreateUserSchema`, monitoring, pgBouncer config, or Service names.
- Known bug K8SPG-1099 (open, fix 3.2.0): removing `spec.standby` instead of setting `enabled: false` leaves the cluster in standby. The doc uses `enabled: false`, so it is OK, but it does not warn.
- The troubleshooting section cites Crunchy issue #4472, a missing `.history` file with async archive.

### 4.2 Method B: backup and restore

**Steps:**

1. Configure the Crunchy repo on S3 and wait for `stanzaCreated`.
2. Stop writes (optional) and take a full backup.
3. Create the Percona Secret.
4. Install the operator.
5. Create the `PerconaPGCluster` with:
   - `dataSource.pgbackrest{stanza: db, repo: repo1 s3, global.repo1-path = Crunchy path}`;
   - a **different** `backups.pgbackrest.global.repo1-path`.
6. Verify, take a post-migration backup, and repoint applications.
7. Delete the Crunchy cluster when done.

**Characteristics:**

- **Downtime:** from the final backup through restore and validation. Writes after the backup are lost unless re-done.
- **Rollback:** point applications back to Crunchy.

**Gaps:**

- **PITR is not mentioned.** `dataSource.pgbackrest.options: ["--type=time", "--target=…"]` could restore to the cutover instant and remove the "stop writes before backup" constraint.
- There is no path for a Crunchy repo on a **PVC**. `dataSource.volumes.pgBackRestVolume` exists in the Percona CRD and could reuse the Crunchy repo PVC (`<cluster>-repo1`) **(inference; [LAB])**.
- Two steps are numbered "2.".
- The "Wrong data" troubleshooting tells users to delete `cluster1` and re-apply. That is fine, but there is no hint about incremental catch-up.
- Users, Secrets, extensions and monitoring are not covered, the same as in A.

### 4.3 Method C: reuse data volumes

**Steps:**

1. Scale Crunchy to 1 replica.
2. Stop writes.
3. Find the primary pod (`role=master`), its `postgres-data` PVC and the PV.
4. Patch the PV to `Retain`.
5. **Remove the PostgresCluster finalizers** and delete it.
6. Uninstall Crunchy.
7. Remove the PV `claimRef`, wait for `Available`, and label the PV.
8. Create the `PerconaPGCluster` with 1 replica and `dataVolumeClaimSpec.selector` matching the label. Percona starts on the existing PGDATA.
9. Remove the selector and scale to 3.
10. Take a new backup on a fresh repo1 volume.

**Characteristics:**

- **Downtime:** from stop-writes until Percona is ready.
- **Rollback:** "least rollback-friendly".

**Gaps:**

- **No clean shutdown first.** Deleting with finalizers removed lets garbage collection kill the pods. Setting `spec.shutdown: true` first gives Patroni a clean checkpoint. The doc only mentions crash recovery.
- **The WAL volume (`walVolumeClaimSpec`/`-pgwal` PVC) and tablespace volumes are ignored.** A Crunchy cluster with a separate WAL PVC would start with a broken `pg_wal` symlink **(inference; [LAB])**.
- Instead of the PV manipulation, the documented-but-unused **`dataSource.volumes.pgDataVolume`/`pgWALVolume`** fields (made usable without `repoName` in 3.1, K8SPG-1119) look like the intended mechanism. The guide does not use them.
- The Crunchy pgBackRest repo is discarded with the cluster, so PITR history is lost. A pre-migration backup is only recommended.
- The same user, Secret and extension gaps apply. This method is the most exposed to the extension DROP, because the database is reused as-is.

### 4.4 Things no Percona document covers

| Topic | Why it matters |
|---|---|
| PGO **v6 / v1 API**, and v5.6/5.7 sources | v6 is Crunchy's current line, and customers will upgrade to it before the EOL deadline |
| A **PostgresCluster to PerconaPGCluster field mapping** | Section 2 of this note is the closest thing to one |
| Secret, password and connection-string continuity; keeping the cluster name | Applications break otherwise (section 3.4) |
| Extension inventory and enabling built-ins | Prevents the DROP hazard; covers Crunchy-only extensions, PostGIS 3.6 vs 3.5, TimescaleDB. In progress as K8SPG-1197. |
| `autoCreateUserSchema` default change | New objects land in user schemas instead of `public` |
| `role=master` vs `role=primary` | Custom selectors break |
| Monitoring migration | pgMonitor/Grafana/Alertmanager to PMM or postgres_exporter; `ccp_monitoring` and `monitor` schema cleanup; OTel |
| pgAdmin | No pgAdmin path at all |
| Helm values mapping; OLM migration | Customers installed Crunchy with these tools |
| pgBouncer configuration and Services/LoadBalancer translation | `service` becomes `expose` |
| TLS/CA continuity | Clients with `verify-ca`/`verify-full` break |
| Backup schedule translation and repo ownership after migration | Schedules run differently; retention may expire Crunchy-era backups |
| Large-scale or multi-cluster migration; OpenShift specifics | Not addressed |
| Logical (`pg_dump`/logical replication) migration | Only mentioned as the fallback for cross-major or cross-architecture moves |

**Smaller inconsistencies:**

- `compare.md` says Percona supports PG "13 - 18". 3.1 supports 14–18, plus 19 as a tech preview.
- The Crunchy column in `compare.md` doesn't mention the EOL.

### 4.5 Jira, GitHub and forum signals

Jira query: `project=K8SPG AND text~crunchy`; 65 issues, read through `/rest/api/3/search/jql`. The old `/rest/api/2/search` returns 410.

| Item | Status | Relevance |
|---|---|---|
| K8SPG-1197 "Documentation bug: Crunchy2Percona Operator migration" (2026-10-09) | In Progress, fix 3.2.0 | Extensions not covered; `shared_preload_libraries` lost; pgvector would be dropped; version mismatches. The maintainer confirms that "our operator will drop the extension when false". |
| K8SPG-1143 "Data corruption risk at documentation" (glibc collation) | Done, 3.1.0 | Led to `migrate-checklist.md` |
| K8SPG-1004 Document migration from Crunchy | Done (3.0.0) | |
| K8SPG-1016 / 1007 Hard fork, CRD rename for coexistence | Done (3.0.0) | Rationale: "upstream Crunchy operator is no longer actively evolving at the pace required" |
| K8SPG-1110 pgAdmin on Percona operator (user migrated from Crunchy) | Open | |
| K8SPG-1129 Need pgAdmin image compatible with Percona operator (partner on OpenShift uses Crunchy pgAdmin image; new image breaks with python 3.12 path) | Open, 3.2.0 | |
| GitHub #1708 Restore pgAdmin support (CRD inherited but non-functional) | Open | Maintainer: "With Crunchy going EOL and migrations happening, people started to ask about pgAdmin. We'll consider supporting it." |
| GitHub #1731 Scheduled backups run twice (CronJob plus in-process scheduler) | Open | Reproduced when schedules are written into the inner PostgresCluster. Relevant to tools that convert CRs. |
| GitHub #1687 / K8SPG-1099 standby removal not propagated | Open (3.2.0) | Reported during a Crunchy migration |
| K8SPG-1198 `pg_stat_statements.track` forced to `all` | In Progress | Performance difference compared with Crunchy defaults |
| K8SPG-968 LDAP bind password as plain string | Open | Affects LDAP users migrating |
| K8SPG-926 Missing sane defaults in the pg-db Helm chart | Open | Helm migrations |

The Percona forum search found no threads specifically about Crunchy migration. Migration questions seem to reach Percona through Support and Jira.

**Sources for section 4**

- https://docs.percona.com/percona-operator-for-postgresql/latest/migrate-from-crunchy.html (and `-standby`, `-backup-restore`, `-data-volumes`, `migrate-checklist`)
- https://github.com/percona/k8spg-docs
- https://www.percona.com/blog/comparing-migration-methods-from-the-crunchy-data-postgresql-operator-to-the-percona-operator-for-postgresql/
- https://perconadev.atlassian.net/browse/K8SPG-1197 , K8SPG-1143, K8SPG-1110, K8SPG-1129, K8SPG-1099, K8SPG-1198
- https://github.com/percona/percona-postgresql-operator/issues/1708 , /1731 , /1687
- https://forums.percona.com (search)

---

## 5. Recommendations: making Crunchy-to-Percona migration seamless

They are prioritised by customer impact and by the EOL deadline (31 Dec 2026, about 11 weeks away).

### P0: before the Crunchy final release (Q4 2026)

1. **Stop the extension DROP from hurting migrated clusters.**
   - What: either make Percona preserve extensions on adoption, or default `DROP` to off. One option is a policy such as `extensions.reconcilePolicy: preserve|enforce`, defaulting to `preserve` for clusters bootstrapped from existing data. Also have the operator detect installed extensions at first reconcile and refuse to drop any that hold objects or data (pg_cron jobs, vector columns).
   - Why: this is the highest-severity silent data and functionality loss found. It is only partly tracked (K8SPG-1197). **[LAB]** should confirm pg_cron job loss and pg_stat_statements/pg_repack drops after method C.
2. **Ship a migration CLI or converter**, for example `kubectl pg migrate-from-crunchy` or a container job.
   - It reads `PostgresCluster` (`v1beta1` **and** `v1`), PGUpgrade, PGAdmin and the operator Deployment env (feature gates, RELATED_IMAGE).
   - It emits a `PerconaPGCluster` using the mapping table in section 2:
     - `service` to `expose`;
     - `shutdown` to `pause`;
     - `paused` to `unmanaged`;
     - TLS fields to `secrets.*`;
     - `instances[].containers` to `sidecars`;
     - `volumes.additional` to `extraVolumes`;
     - schedules kept in the outer CR only;
     - `autoCreateUserSchema: false`;
     - required gates (AutoGrowVolumes, TablespaceVolumes).
   - It also produces a **preflight report**:
     - PG major, architecture, UBI/glibc/ICU and collation versions;
     - the extension inventory per database compared with the Percona image (flag pg_partman, TimescaleDB, PostGIS 3.6, pgnodemx and others);
     - `shared_preload_libraries` content;
     - unsupported fields (instrumentation, monitoring, userInterface, `patroni.logging`, `disableDefaultPodScheduling`, Service trafficPolicy/ipFamilies);
     - Secrets to copy;
     - selectors using `role=master`.

     The preflight report alone would answer most of K8SPG-1197.
3. **Secret and TLS continuity built in.** Add a documented and tested option to:
   - keep the **same cluster name**;
   - pre-seed `pguser` Secrets (password plus verifier) so passwords are not regenerated;
   - import `pgo-root-cacert` as `customRootCATLSSecret` so clients that verify the CA keep working.

   Replace the standby guide's reuse of Crunchy leaf certificates with this.
4. **Explicit PGO v6 / `v1` API support and a test matrix.** Run e2e migrations from CPK 5.6, 5.7, 5.8.9 and 6.0.3 (both API versions) on S3 and PVC repos, with and without a WAL PVC, tablespaces, PostGIS and pgBouncer. Publish the matrix in the docs. The docs currently claim only 5.8.x.
5. **Documentation hub "Migrating from Crunchy PGO"**, as a single page including:
   - the CPK final-release facts and the Developer Program implications (image mirroring, production use needing a subscription for 50+ employee organizations);
   - a decision tree that adds a logical method for cross-major, cross-architecture or extension-incompatible cases;
   - the field mapping table;
   - a "What is NOT migrated" list: users and passwords, Secrets, monitoring, pgAdmin, OTel, Crunchy-only extensions, dashboards, CronJob schedules, `kubectl pgo` workflows;
   - a post-migration checklist: rotate to Percona TLS, retention on the shared repo, remove `ccp_monitoring` and the `monitor` schema, check `pg_stat_statements.track`, `autoCreateUserSchema`, label selectors;
   - fixes for the doc errors in 4.1–4.3: step numbering, `-l` duplication, the backup.yaml file name, the shutdown before PV reuse, WAL and tablespace PVCs, using `dataSource.volumes`, PITR cutover, the PVC repo path, and PG 13–18 in `compare.md`.

### P1: next 1–2 releases (3.2 / 3.3)

6. **In-place adoption ("take over") of a running Crunchy cluster with no data copy.**
   - Feasibility: PGDATA paths, labels, Service names, Secret formats, pgBackRest stanza and Patroni label scheme are already identical.
   - Mechanism: the Percona operator could adopt a stopped Crunchy cluster's PVCs, Secrets and Services. It would rewrite ownerReferences, keep the Patroni scope and DCS, and roll pods onto Percona images one at a time. Downtime would be a rolling restart, and PITR history would be kept.
   - Requirements: matching UBI and extensions, and handling `role=master` to `role=primary` during the rollout.
   - Payoff: this is the strongest possible differentiator against CloudNativePG, which needs a data copy.
7. **Crunchy-compatible images.**
   - Ship PostGIS 3.6 for PG17/18. It is already Crunchy's only option on PG18.
   - Ship pg_partman and pg_jobmon (very common in Crunchy shops), orafce, hypopg, pgrouting and pg_parquet, as built-ins or an "extended" image or extension bundle.
   - Document TimescaleDB as custom (licence caveats).
   - Keep the UBI 8/9 variants (3.1) as the default recommendation, matched to the source UBI.
8. **Monitoring parity.**
   - (a) A first-class `monitoring.prometheusExporter` option that deploys postgres_exporter, with an optional **pgMonitor-compatible query set** (`ccp_*` metric names) so existing Crunchy Grafana dashboards and alert rules keep working.
   - (b) A PMM guide for users of Crunchy dashboards.
   - (c) An OTel path: Fluent Bit logs already work; add OTel metrics, or accept Crunchy's `instrumentation` exporter endpoint semantics.
   - (d) Cleanup of `ccp_monitoring` and `pgnodemx`.
   - (e) Reconsider PMM's `monitor` user being SUPERUSER.
9. **pgAdmin.** Revive the inherited `PGAdmin` controller, or ship a supported pgAdmin image and Helm chart (GitHub #1708, K8SPG-1110, K8SPG-1129). OpenShift partners are blocked on this today.
10. **Compatibility switches:**
    - optional extra label `role=master` on the primary for a deprecation window;
    - `autoCreateUserSchema` default false for migrated clusters;
    - feature-gate parity with v6 (AutoGrowVolumes and sidecars on, autoGrow thresholds);
    - `patroni.logging`, `disableDefaultPodScheduling`, Service `externalTrafficPolicy`/`ipFamilies`, and `instances.volumes.temp`.
11. **Fix migration-adjacent bugs:** #1731 (double scheduled backups), K8SPG-1099 (standby removal), K8SPG-1198 (track=all), K8SPG-968 (LDAP password).
12. **Helm and OLM.** Publish a Crunchy `pgo` Helm values to `pg-operator`/`pg-db` mapping. Make sure `pg-db` can express everything the converter emits (K8SPG-926). Document side-by-side OLM installs on OpenShift: both operators were in all-namespaces mode before the 3.0 scoping fix.

### P2: nice to have

13. A `kubectl` plugin with parity for common `kubectl pgo` workflows: backup, restore, `support export`, start/stop.
14. Commercial and positioning work:
    - a "Crunchy CPK exit" support offering, with fixed-price migration and assessment using the preflight tool;
    - a public comparison page that states the image-licence difference (Percona images free for production; Crunchy's need a subscription for 50+ employee organizations);
    - Percona-hosted mirrors or instructions to rebuild Crunchy images from `components/` for customers who need time.
15. A blog or tutorial on a logical-replication method (`pg_createsubscriber` or the 3.1 logicalReplicas machinery) for cross-major-version migrations: Crunchy PG15 to Percona PG18 in one step.

### What the k3s lab should verify, in priority order

1. Extension DROP behaviour after methods B and C, with pg_cron jobs, pg_stat_statements, pg_repack and pgvector present.
2. Password regeneration versus pre-seeded Secrets, and the `users[].secretName` adoption path.
3. A CPK **6.0.3** source (`v1` API, logs outside PGDATA) with each method.
4. Method C with a separate WAL PVC; `dataSource.volumes.pgDataVolume`/`pgWALVolume` as an alternative.
5. Importing `pgo-root-cacert` as `customRootCATLSSecret`, with `verify-full` clients.
6. A PostGIS 3.6 database onto Percona 3.5.7.
7. Same-name/same-namespace coexistence risk (non-production only).
8. Retention behaviour on the shared repo after standby promotion.
