# CloudNativePG: isolated primary, split-brain and lost writes after failover. Public reports and what to test

*Prepared 2026-10-14. This is desk research only: GitHub issues, PRs and Discussions read via `gh`, the CNPG source and docs at tag `v1.30.1`, and blogs. Nothing was run against any server.*
*Current release: **1.30.1** (tag `v1.30.1` = `2a35abb46`, 2026-09-23). 1.31 is not released. Milestone `1.31.0` holds the lease self-fencing rework.*

How I checked whether a fix is in 1.30.1:
- For PRs merged to `main` before 1.30 was branched, `gh api repos/.../compare/<merge-sha>...v1.30.1` returns `ahead`, meaning the fix is included.
- For later fixes I looked for the backport commit on `release-1.30` dated before the tag (`gh api repos/.../commits?sha=release-1.30&since=...`).
- Each case is noted in the tables.

---

## 0. TL;DR

1. **The isolated-primary write window is still present in 1.30.1 with default settings.** This is #11280. It is open, has milestone 1.31.0, and no backportable fix exists.
   - The isolation check only fails the liveness probe. The kubelet then sends SIGTERM, and the instance manager runs a **smart** shutdown.
   - Sessions that were already open keep committing for up to `smartShutdownTimeout` (180 s by default), on top of about 30 s of detection.
   - Two fix PRs were closed without merging: #11283 (fast shutdown) and #11504 (immediate shutdown).
   - The only change in 1.30.1 is documentation (#11518), which now admits the window.
   - The real fix is lease-based self-fencing (#11357 and #11358). Both are open PRs marked "do not backport", so they arrive in 1.31 only.
2. **The isolation check is blind in some partition shapes.** It fires only when the API server is unreachable **and** the `/failsafe` call on port 8000 fails for at least one peer. In 1.30.1 any single unreachable peer is enough to trip it (#11641).
   - If the primary loses the API server but can still reach peers on 8000, the check never fires.
   - 1.30.1 has no rule of the form "a peer told me someone else is the target primary". That rule is what #11357 adds in 1.31.
   - Our lab test t6 (API loss on the primary's node) matches this: the node went NotReady at +47 s, but no failover happened and the primary was never restarted. New connections to `-rw` failed for 136 s.
3. **1.30.1 closed several lease and failover gaps. Re-test these as regressions.**
   - #11356: PostgreSQL startup is now gated on holding the lease. Before this, a restarted isolated primary could come back up as primary.
   - #11350: the lease `Get` call is now bounded.
   - #11336: a pending failover could be silently reverted.
   - #11347: an unreachable old primary is now demoted immediately.
   - #11274: a fenced instance no longer blocks failover.
   - #11263: the fast shutdown is no longer abandoned at 60 s.
4. **Lost writes during switchovers with quorum sync replication are still open.**
   - #11114: primary update switchover.
   - #11293: automatic switchover when the primary's node is cordoned or tainted.
   - In both, the new primary is chosen *before* the old primary stops accepting writes.
   - Fix PRs #11185 and #11294 are open and unmerged, so the bug is present in 1.30.1.
5. **Gaps where failover never happens (availability, not split-brain).** These remain open or were closed as stale without a fix:
   - #10591: a walsender survives on a zombie node and blocks failover. Open, milestone 1.31.
   - #10678: the write path is wedged but `/pg/status` still reports healthy. Closed as stale, not fixed.
   - #11655: a barman-cloud plugin pod on the failed node blocks failover for about 400 s. Filed today.
6. **Maintainers' position:**
   - Synchronous replication (`dataDurability: required`, quorum `ANY`) is the answer for data durability.
   - For async clusters, set `smartShutdownTimeout: 0`. Coroot also suggests `failoverDelay` ≥ 30 s.
   - Sync replication on by default is being discussed (Discussion #10783). So far only a warning exists (#11148), and it is not in 1.30.1.

---

## 1. Mechanism reference for 1.30.1 (from source and docs at the tag)

| Component | Behaviour in 1.30.1 | Source |
|---|---|---|
| Liveness probe on a primary | If the API server is reachable, it returns OK. The pinger runs but only logs. If the API server is **un**reachable, it runs `ensureInstancesAreReachable`, which GETs `https://<ip>:8000/failsafe` on every instance in `status.instancesReportedState` and **returns the first error**. So one unreachable peer is enough to fail the probe. Replicas always return OK. Defaults: `livenessProbeTimeout` 30 s, which gives period 10 s and failureThreshold 3; isolation `requestTimeout` and `connectionTimeout` are both 1000 ms. | `pkg/management/postgres/webserver/probes/liveness.go`, `pinger.go` |
| What the kill does | The kubelet sends SIGTERM. The lifecycle loop calls `TryShuttingDownSmartFast`: a CHECKPOINT, then `pg_ctl stop -m smart -t smartShutdownTimeout` (180 s), then fast (bounded by `stopDelay` since #11263). | `internal/cmd/manager/instance/run/lifecycle/lifecycle.go` |
| Primary lease | Defaults: `leaseDurationSeconds` 15, `renewDeadlineSeconds` 10, `retryPeriodSeconds` 2, `releasedLeaseDurationSeconds` 1. A promoting replica must hold the lease. After an abrupt loss it must see the lease unchanged for a full `leaseDurationSeconds`. | `docs/src/failover.md` (v1.30.1), `internal/cmd/manager/instance/run/lease/runnable.go` |
| Primary that cannot renew | `leaseUnverifiable` (API server unreachable): it logs "Primary lease lost, cannot verify holder, retrying" and **keeps running**. Fencing is left to the liveness probe. `leasePreempted` (it can read the lease and someone else holds it): it returns a fatal error, the manager context is cancelled, and the lifecycle `ctx.Done()` branch calls **`TryShuttingDownSmartFast`**. That would be a smart shutdown again; it needs a test (see T2). | `runnable.go` lines ~425-560, `lifecycle.go` ~120-135 |
| Startup | Since #11356 (in 1.30.1), a PGDATA that is already primary must acquire the lease before PostgreSQL starts. An isolated primary restarted by the kubelet therefore should **not** come back as primary. | release notes 1.30.1 |
| Operator failover trigger | The operator relies on the pod `Ready` condition. For a node-level loss, that flips about 40-55 s after the node becomes unreachable (`node-monitor-grace-period`). #10445 (in 1.30.0): if `/pg/status` fails but the pod is still Ready, the operator defers and requeues instead of failing over. Failover sets `targetPrimary` to the pending marker and strips the `cnpg.io/instanceRole=primary` label from the old pod (#10409, in 1.30.0). It then **waits for all WAL receivers to be down** (`AreWalReceiversDown`), then picks the most advanced replica. That replica takes the lease and promotes. | `docs/src/failover.md`, #10403, #10445, #10591 |
| Switchover paths | `updatePrimaryPod` (rolling update) and `setPrimaryOnSchedulableNode` (cordoned or tainted node) **pick the target before the old primary stops**, skip the quorum check, and do not use the pending-marker sequence. | #11114, #11293 |

Implications for partition design:
- Whether the isolation check fires depends only on two things: whether the pod can reach the API server (ClusterIP 10.43.0.1:443, which maps to control-plane:6443), and whether it can reach port **8000** on peers.
- It does not depend on port 5432 or on kubelet probes. Blocking 5432 alone never fires the check.
- If the partition also blocks the node's `cni0` gateway IP (10.42.X.1), kubelet HTTP probes time out. The kill then happens because of probe timeouts, not because of the isolation logic. Coroot blocked the CNI bridge IPs, so in their run both effects were mixed.
- Existing TCP sessions survive label and endpoint changes. Conntrack keeps the DNAT to the old pod IP. Only new connections follow the Service.
- On an API-isolated node, kube-proxy keeps its last rules. New connections from that node still reach the old primary (#7407).

---

## 2. Catalogue of public reports

The table gives one line per issue. Mechanism details follow below it.

| # | Report (links) | Date / reported ver | Status (2026-10-14) | Fix in 1.30.1? |
|---|---|---|---|---|
| A | [#7407](https://github.com/cloudnative-pg/cloudnative-pg/issues/7407) Split-brain in case of network partition (Nikolay Samokhvalov, postgres.ai); discussion [#7462](https://github.com/cloudnative-pg/cloudnative-pg/discussions/7462) | 2025-04-22, 1.25.1 | Closed 2025-04-30 (milestone 1.26). Led to the isolation checker [#7465](https://github.com/cloudnative-pg/cloudnative-pg/issues/7465) (experimental in 1.26) and [#7551](https://github.com/cloudnative-pg/cloudnative-pg/issues/7551) (GA and default-on in 1.27) | Partially. The isolation check exists but has the windows in B, C and D |
| B | [#11280](https://github.com/cloudnative-pg/cloudnative-pg/issues/11280) Isolation check does not stop an isolated primary from accepting writes (smart shutdown); based on [Coroot blog](https://coroot.com/blog/reproducing-split-brain-on-cloudnativepg/) | 2026-07-30, 1.30.0 | **Open**, milestone 1.31.0. Fix PRs [#11283](https://github.com/cloudnative-pg/cloudnative-pg/pull/11283) and [#11504](https://github.com/cloudnative-pg/cloudnative-pg/pull/11504) **closed unmerged**. Docs [#11518](https://github.com/cloudnative-pg/cloudnative-pg/pull/11518) merged and backported (`4b4ba674e` on release-1.30). Real fix is [#11357](https://github.com/cloudnative-pg/cloudnative-pg/pull/11357) and [#11358](https://github.com/cloudnative-pg/cloudnative-pg/pull/11358), both open and "do not backport" | **No**, docs only |
| C | [#11641](https://github.com/cloudnative-pg/cloudnative-pg/issues/11641) Isolation check restarts a healthy primary when only one replica is unreachable; same root cause as [#10287](https://github.com/cloudnative-pg/cloudnative-pg/issues/10287) | 2026-10-10, 1.30.1 (RKE2) | Open, untriaged. #10287 was closed as stale (not planned) on 2026-09-29 | No (false positive, availability) |
| D | Isolation-check blind spot: API lost but peers reachable on 8000. From the code plus #11357's description ("a peer being reachable doesn't mean it hasn't already been promoted"). Our lab test t6 showed the stall variant | n/a | Addressed only by #11357 (1.31) | **No** |
| E | [#10403](https://github.com/cloudnative-pg/cloudnative-pg/issues/10403) Primary label not removed during failover, so `-rw` routes to the stale primary | 2026-04-01, main | Fixed by [#10409](https://github.com/cloudnative-pg/cloudnative-pg/pull/10409) (merged 2026-04-20; in v1.30.0, compare=ahead) | Yes |
| F | [#10423](https://github.com/cloudnative-pg/cloudnative-pg/issues/10423) / [#10430](https://github.com/cloudnative-pg/cloudnative-pg/issues/10430) Failover on an HTTP check failure while the pod is still Ready (VM live migration or pause) could end with two primaries | 2026-04-08 / 04-11, 1.29 | #10423 closed as stale (not planned) on 2026-10-09. #10430 open and stale. Community PR [#10428](https://github.com/cloudnative-pg/cloudnative-pg/pull/10428) open and unreviewed. **However**, maintainer PR [#10445](https://github.com/cloudnative-pg/cloudnative-pg/pull/10445) (merged 2026-04-22, in v1.30.0) already defers failover while the pod is Ready, and [#10509](https://github.com/cloudnative-pg/cloudnative-pg/pull/10509) adds a `PrimaryStatusCheckFailed` event | Mostly. A pause longer than the node grace period (~40-55 s) still causes failover, followed by a resumed old primary (see G) |
| G | [Discussion #9814](https://github.com/cloudnative-pg/cloudnative-pg/discussions/9814) (Franck Pachot): a 30 s cgroup freeze of the primary led to the operator "failing over to itself" about 3 minutes later and killing sessions. Gabriele Bartolini wrote `freeze.sh` (cgroup.freeze) to reproduce | 2026-01-27, 1.28.0 | Under investigation, no resolution posted | Unknown. Re-test (the colleague's VM-pause test) |
| H | [#10678](https://github.com/cloudnative-pg/cloudnative-pg/issues/10678) `/pg/status` reports healthy while the write path is wedged (EBS pause-volume-io); no failover for hours | 2026-05-12, 1.28.0 (EKS) | Closed as stale (not planned) on 2026-10-11. No fix | No (availability) |
| I | [#10591](https://github.com/cloudnative-pg/cloudnative-pg/issues/10591) Failover blocked indefinitely while a walsender survives on a zombie node (storage dead, kernel alive). Repro: SIGSTOP kubelet, PID 1 and postmaster, leave walsenders running | 2026-05-01, 1.28.2 | **Open**, milestone 1.31.0. Fix direction: [#11367](https://github.com/cloudnative-pg/cloudnative-pg/pull/11367) "promote without waiting for WAL receivers" (open, "do not backport"), which depends on the lease | No |
| J | [#11346](https://github.com/cloudnative-pg/cloudnative-pg/issues/11346) Failover silently reverted or stalled while target = pending marker | 2026-08-20, 1.30.0 | Fixed by [#11336](https://github.com/cloudnative-pg/cloudnative-pg/pull/11336) (`e4c83490a` on release-1.30, 2026-09-19) | **Yes** |
| K | [#11348](https://github.com/cloudnative-pg/cloudnative-pg/issues/11348) / [#11347](https://github.com/cloudnative-pg/cloudnative-pg/pull/11347) Unreachable old primary never demoted during failover | 2026-08-20, 1.30.0 | Fixed (`aefbab839`, 2026-09-17) | **Yes** |
| L | [#11354](https://github.com/cloudnative-pg/cloudnative-pg/issues/11354) PostgreSQL started before lease acquisition on primary restart (1.30.0 only) | 2026-08-21, 1.30.0 | Fixed by [#11356](https://github.com/cloudnative-pg/cloudnative-pg/pull/11356) (`b5f4e2552`, 2026-09-15) | **Yes** |
| M | [#11349](https://github.com/cloudnative-pg/cloudnative-pg/issues/11349) Lease take-over `Get` unbounded, which could delay the primary's own renewal and cause an unwanted take-over | 2026-08-20, 1.30.0 | Fixed by [#11350](https://github.com/cloudnative-pg/cloudnative-pg/pull/11350) (`72075f048`) | **Yes** |
| N | [#11114](https://github.com/cloudnative-pg/cloudnative-pg/issues/11114) Primary-update switchover chooses the target before the old primary stops (ANY 1 quorum sync means acknowledged commits can be on the non-chosen replica) | 2026-07-02, 1.29 (GKE) | **Open** (stale label). PR [#11185](https://github.com/cloudnative-pg/cloudnative-pg/pull/11185) open | **No** |
| O | [#11293](https://github.com/cloudnative-pg/cloudnative-pg/issues/11293) Same race in the cordoned or tainted node auto-switchover (Karpenter `disrupted` taint); 45 COMMIT records on the replica that was ahead | 2026-08-04, 1.30.0 (EKS) | **Open**. PR [#11294](https://github.com/cloudnative-pg/cloudnative-pg/pull/11294) open | **No** |
| P | [#8701](https://github.com/cloudnative-pg/cloudnative-pg/issues/8701) Distributed topology: a lagging local standby was promoted while remote replicas (in `FIRST 1`) were ahead; pg_rewind discarded commits | 2025-10-01, 1.25.1 / 1.27 | Closed as stale (2025-12-22). Maintainers: cross-cluster awareness is out of scope. `failoverQuorum` now refuses `FIRST` configs | Won't fix (architecture) |
| Q | [#11307](https://github.com/cloudnative-pg/cloudnative-pg/issues/11307) Future-timeline guard bypassed in established replica clusters (`status.timelineID` = 0); stale `.history` from an obsolete branch is restored | 2026-08-10 | Open | No (replica clusters only) |
| R | [#7901](https://github.com/cloudnative-pg/cloudnative-pg/issues/7901) / [#7732](https://github.com/cloudnative-pg/cloudnative-pg/issues/7732) Liveness probe calls the API server, so it timed out on a slow API server and restarted the container | 2025-06, 1.26 | Closed (superseded by the 1.27 isolation-check logic) | Re-test (T8) |
| S | [#11655](https://github.com/cloudnative-pg/cloudnative-pg/issues/11655) Unreachable barman-cloud plugin pod blocks failover for about 400 s (k3s 1 + 3 lab, local-path; looks like our lab) | 2026-10-14, 1.30.1 | Open | No (availability) |
| T | [#11110](https://github.com/cloudnative-pg/cloudnative-pg/issues/11110) `cnpg restart` switches over to a replica whose replay is lagging, leaving 14 min without a writable primary | 2026-07-01, 1.28 | Open. Maintainer: an availability gap, separate from the correctness work | No |
| U | [#7481](https://github.com/cloudnative-pg/cloudnative-pg/issues/7481) Failover quorum design (ardentperf). Became `failoverQuorum`: experimental in 1.27, stable in 1.28 | 2025-05 | Feature shipped | n/a |
| V | [#10807](https://github.com/cloudnative-pg/cloudnative-pg/issues/10807) / [#10627](https://github.com/cloudnative-pg/cloudnative-pg/pull/10627) Primary lease. [#10950](https://github.com/cloudnative-pg/cloudnative-pg/pull/10950) set the default retry to 2 s | 2026-05/06 | Shipped in 1.30.0 | n/a |

### 2.1 Details per scenario

**A. #7407: network partition of the primary node (postgres.ai)**
- *Trigger:* kind with 1 control-plane and 3 workers; 3-instance async cluster with defaults. `docker network disconnect` of the primary's node container (a full node partition).
- *Observed:* a replica is promoted, and the old pod is still a read-write primary. Workloads on the isolated node, or in the isolated AZ, keep connecting through **stale kube-proxy iptables**. pg_cron or other internal writes continue.
- *Maintainers in 2025-04:* async replication means accepting data loss and choosing availability over consistency (CAP); use sync replication, anti-affinity and dedicated nodes. They then built the isolation checker.
- *Further points from the thread:*
  - bonesmoses compared this with Patroni's leader key and REST routing.
  - Leonardo Cecchi noted that kube-proxy staleness affects Patroni on Kubernetes too.
  - Nikolay pointed out that sync replication is not a complete fix: cancelling a sync-rep wait makes the commit visible locally (pgsql-hackers thread by Andrey Borodin). See T4b.

**B. #11280 and the Coroot blog ("Reproducing split-brain on CloudNativePG", Nikolay Sivko, 2026-07-29)**
- *Setup:*
  - CNPG 1.30.0, PostgreSQL 18.4, 3 instances, async replication, all defaults (`failoverDelay: 0`, `smartShutdownTimeout: 180`, isolation check on).
  - Chaos Mesh NetworkChaos on the pod `cnpg.io/instanceName=postgres-splitbrain-1` blocked replicas, the operator pods (`cnpg-system`), the API server (10.43.0.1 and endpoint), the node CNI bridge IPs (4) and the node IPs (4).
  - The **clients were not blocked**: three Go writers with persistent connections through `-rw`, inserting `bigserial` rows.
- *Timeline:*

  | Time | Event |
  |---|---|
  | t+0 (18:11:20) | Partition applied |
  | t+34 s | Liveness kill |
  | t+37-38 s | Operator FailingOver, new primary chosen |
  | t+117 s (18:13:17) | New primary's first write; clients reconnect only after their old sessions end |
  | t+215 s | Old primary's last ack, which is 34 s plus the 180 s smart shutdown |

  **Both primaries acknowledged writes for about 99 s.**
- *Damage:*
  - 1,472 acknowledged writes after the split.
  - 291 rows lost (removed by pg_rewind).
  - 562 ids "stolen": the same id now belongs to a different row from another client.
- *Second run* with `smartShutdownTimeout: 0` and `failoverDelay: 30`: the old primary stopped at t+34 s, with 0 s overlap. 21 rows still lost and 109 ids stolen, all from async lag at the moment of failover.
- *Maintainer comments on #11280:*
  - Fast shutdown was preferred over immediate, because pg_rewind needs a clean shutdown (mnencia).
  - Gabriele Bartolini (2026-09-14): #11283 was closed because the probe mechanism is being removed in favour of #11357 and #11358. Those are 1.31-only, and the 1.29.x/1.30.x gap is "not acceptable", so the issue stays open for a backportable fix.
  - mnencia (2026-09-21): #11504 was closed because CI showed it triggering on ordinary transient connectivity problems. The fix direction moved to the lease in 1.31, with docs improved in the meantime. There is also a plan to expose separate smart, fast and immediate timeouts.
- *Status for 1.30.1:* the only mitigation is configuration, `smartShutdownTimeout: 0`, optionally with `failoverDelay`. Even then the first window remains: about 30-34 s of fully open primary before the kill. Async lag at the moment of failover is also lost, by design.

**C. #11641 / #10287: false-positive isolation**
- *Trigger:* the node of one replica is powered off, and **at the same time** the primary cannot reach the API server within 1 s for about 30 s (an API server endpoint was on the lost node, which happens with HA control planes). #10287 instead used chaos-mesh with a 10 s delay towards one replica.
- *Observed:* the healthy primary is restarted. Clients see an outage of about 21 s, with no failover.
- *Workaround:* disable `isolationCheck`.
- This matters for split-brain testing because it shows the check is more aggressive than the documentation says: **any** one peer unreachable is enough.

**D. Blind spot: the primary loses the API server, but peers' port 8000 stays reachable**
- The liveness probe stays OK, so the old primary is never restarted.
- If the kubelet on that node also loses the API server (node-level partition from the control plane only), the node goes NotReady at about 40-55 s.
- The pod Ready condition is flipped by the node controller, failover starts and the label is stripped.
- Then:
  - (a) If the replicas are still streaming from the old primary, the WAL-receiver gate blocks promotion indefinitely. The result is an outage for new connections, while persistent sessions keep writing to the old primary. This matches lab test t6: node NotReady at +47 s, `currentPrimary` unchanged, 136 s write outage on new connections, recovery only after the heal.
  - (b) If the replicas' WAL receivers drop (5432 blocked, 8000 open, or the walsender killed), I expect a replica to be promoted while the old primary keeps running indefinitely for persistent clients and for same-node clients. That is a real, unbounded split-brain. Not publicly reported; it is a hypothesis derived from the code (see T1).

**E. #10403 (fixed by #10409 in 1.30.0):** the old primary keeps the `cnpg.io/instanceRole=primary` label during failover. Also, when both pods report primary, `ReconcileMetadata` was skipped, so `-rw` routed to both.

**F/G. Pause or freeze (VM live migration):**
- On 1.29 the operator could fail over on a single `/pg/status` timeout while the kubelet was frozen and the pod still Ready. On resume, the old primary is still a running primary.
- 1.30 includes #10445 (defer while Ready). The residual risk is a freeze long enough that the node controller flips Ready (more than ~40-55 s), or any freeze longer than the lease duration combined with another failover trigger.
- On resume, the old primary first runs with clients that are still connected. It must notice the change through either:
  - (i) the instance-manager watch seeing `targetPrimary != self`, which runs `reconcileOldPrimary` and then the fast or immediate shutdown (#11347), or
  - (ii) the lease being preempted, which exits the manager and gives a **smart** shutdown (see §1).
- Which one wins decides whether the post-resume window is about 1 s or up to 180 s. Worth measuring (T2).

**H/I. Write-path wedge and zombie walsender:**
- A storage stall (EBS pause, dead NVMe) leaves `/pg/status` and probes green (read-only queries), so there is no failover for hours. That is an availability problem.
- If failover is attempted, walsender keepalives keep the replicas' WAL receivers "active", so `AreWalReceiversDown` blocks forever.
- For split-brain this is mostly a no-failover outcome, but #11367 (1.31) removes the WAL-receiver gate. That makes zombie-node scenarios a correctness question in 1.31.

**N/O. Switchover races (#11114, #11293):**
- *Trigger:* quorum sync (`method: any, number: 1, dataDurability: required, failoverQuorum: true`) and either a restart-requiring parameter change with `primaryUpdateMethod: switchover`, or cordon/taint of the primary's node.
- The operator selects the target (by received LSN) while the old primary is still accepting writes. The old primary gets acknowledgements from the *other* replica, the chosen target lacks those commits, and after promotion the more advanced replica crash-loops with "requested starting point ... is not in this server's history".
- Evidence: 45 COMMIT records in the reporter's `pg_waldump`, and a 5-instance report from @chadlangston.
- ardentperf questioned whether the commits were acknowledged to clients and asked for Jepsen-style client-side verification. **Nobody has yet shown client-acknowledged loss with a ledger.** That makes it a high-value lab test (T5).
- In 1.30.1 the lease does not help: the old primary releases the lease cleanly, then the chosen target promotes.

**P. #8701:** this is architecture (distributed topology, with failover decided locally). Not testable on a single k3s cluster.

### 2.2 Other public material

- **ardentperf (Jeremy Schneider):**
  - [Run Jepsen against CloudNativePG to see sync replication prevent data loss](https://ardentperf.com/2025/09/01/run-jepsen-against-cloudnativepg-to-see-sync-replication-prevent-data-loss/) (2025-09-01). Two instances, repeated primary pod kills, Jepsen append workload. With async: 22 failures in 93 iterations over 12 h. With sync: none.
  - Harness: [ardentperf/cnpg-playground/lab](https://github.com/ardentperf/cnpg-playground/tree/main/lab).
  - His stated caveat: the failsafe "does not prevent data loss during network partitions"; only sync replication does.
  - KubeCon talk with partition scenarios at about 20 min: https://youtu.be/iQUOO3-JRK4?t=1200
  - Very active on #11280, #11293, #11114 and #10783.
- **Discussion [#10783](https://github.com/cloudnative-pg/cloudnative-pg/discussions/10783), "Default to Synchronous Replication"** (2026-05-26, ardentperf):
  - Proposal: for 3 or more instances, `any`, `number = instances-2` or about half the replicas, with `required`.
  - Phase 1 delivered as the warning [#11148](https://github.com/cloudnative-pg/cloudnative-pg/pull/11148). It is on main only ("do not backport"), so not in 1.30.1.
  - Gabriele also suggests default `streaming` startup and readiness probes and required anti-affinity. No default change has been decided.
- **Discussion [#11364](https://github.com/cloudnative-pg/cloudnative-pg/discussions/11364):** `failoverDelay` and `leaseDurationSeconds` act in different phases. With an abrupt loss, roughly failoverDelay, plus detection, plus lease TTL.
- **Discussion [#11186](https://github.com/cloudnative-pg/cloudnative-pg/discussions/11186):** quorum arithmetic (R+W>N). It notes that failoverQuorum protects acknowledged sync commits and **is not** a split-brain mechanism, and that the switchover path does not apply the quorum gate.
- **CNPG chaos testing (LFX):** https://cloudnative-pg.io/blog/lfx-chaos-testing-yash-agarwal/ uses LitmusChaos and a Jepsen consistency job at 50 ops/s.
- **EDB:** no specific post on the isolation checker or the lease was found. The docs are the reference: https://cloudnative-pg.io/docs/1.30/failover/ and `instance_manager.md#primary-isolation`.
- **Hacker News / Reddit:** no substantive thread found on Coroot's post or #7407.
- **Reference for comparison:** Pigsty's partition notes for Patroni: https://pigsty.io/docs/concept/ha/failure/partition/

---

## 3. Maintainer-recommended mitigations (as of 1.30.1)

| Knob | Effect | Caveat |
|---|---|---|
| `spec.smartShutdownTimeout: 0` | Liveness kill goes straight to fast shutdown, which closes the window of up to 180 s (#11280, docs #11518) | Also affects planned restarts and drains (sessions are cut) |
| `spec.failoverDelay: N` | Delays the start of failover. Coroot: 30 s together with smartShutdownTimeout 0 gave 0 s overlap. Alternatively failoverDelay > 34 + smartShutdownTimeout | Longer RTO |
| `spec.postgresql.synchronous: {method: any, number: ≥1, dataDurability: required, failoverQuorum: true}` | The isolated primary blocks on COMMIT, so no acknowledged writes are lost on failover (Jepsen, ardentperf) | Cancelling a sync wait gives local visibility (T4b). Does not cover the switchover races N/O (they were reported *with* this config). Writes stall if quorum is lost |
| `spec.primaryLease.*` | Larger TTL holds promotion back longer | Does **not** fence an isolated primary in 1.30.x |
| `spec.probes.liveness.isolationCheck.{requestTimeout,connectionTimeout}` | Raise for slow clouds, to reduce false positives (#11641) | Slower fencing |
| `livenessProbeTimeout` / explicit liveness probe | Sets detection (~30 s) | Lower values mean faster fencing but more false positives |
| `primaryUpdateMethod: restart` | Workaround for #11114 | Longer downtime on updates |
| Anti-affinity, dedicated nodes, clients not co-located with the primary | Reduces stale kube-proxy exposure (#7407) | Does not help persistent connections |
| Plugin with 2 or more replicas plus anti-affinity | #11655 | |

---

## 4. Prioritized ADDITIONAL hands-on tests for 1.30.1

Already covered by the colleague: (1) a Coroot-style pod network partition with persistent clients; (2) VM-pause approximation with cgroup freeze of the pod plus SIGSTOP of the kubelet. Lab test t6 (API loss of the primary's node) also exists; T1 extends it.

### Common harness for every test

**Writers.** Use the existing `sb/writer.sh` / `analyze_sb.py` approach and extend it so every acknowledged commit is attributed to a server.
- Run three kinds of writer:
  - **persistent** connections to `-rw` from a pod on a *different* worker;
  - **persistent** connections from a pod on the *primary's* worker;
  - **new connection per write** from both.
- Each insert should be `INSERT ... RETURNING id, inet_server_addr(), pg_postmaster_start_time(), (SELECT timeline_id FROM pg_control_checkpoint()), now()`.
- Log `client_id, seq, uuid` and the ack time to a local file *before and after* the commit.

**After the test.**
- Compare the acknowledged uuids against the final table on the surviving timeline. Report:
  - LOST: acknowledged but missing;
  - STOLEN: id reused;
  - the dual-ack window, from the first ack on the new primary to the last ack on the old primary.
- **Before healing or rewind**, copy the old primary's PGDATA from `/var/lib/rancher/k3s/storage/pvc-*` on its node, or at least `pg_wal`, so that `pg_waldump` can count the divergent commits.

**Timestamps to record.** Collect every 1 s from a control-plane-side loop:
- `kubectl get cluster -o jsonpath='{.status.currentPrimary}{.status.targetPrimary}{.status.phase}'`
- `kubectl get lease <cluster> -o jsonpath='{.spec.holderIdentity} {.spec.renewTime}'`
- pod Ready condition
- `-rw` EndpointSlice addresses
- events (`Killing`, `FailingOver`, `PrimaryStatusCheckFailed`)

Also collect instance-manager logs from the old primary through `crictl logs` on the isolated node, because the API is unavailable there.

**Lab facts (k3s).**
- API server: `10.43.0.1:443`, which maps to `<cp-ip>:6443`. Agents use a local LB on `127.0.0.1:6444` → `<cp-ip>:6443`.
- Pod CIDR `10.42.0.0/16`; kubelet probes come from `10.42.<n>.1` (`cni0`); flannel VXLAN on UDP 8472 between node IPs.
- Instance manager on `:8000` (https, `/failsafe`, `/pg/status`); PostgreSQL on `:5432`.

### T1 (P1). Control-plane-only partition of the primary's node (isolation-check blind spot, scenario D). Two variants

*Why:* in 1.30.1 the isolation check never fires while peers answer on 8000. If failover completes anyway, nothing stops the old primary. #11357 (1.31) exists precisely to close this.

*Setup:* 3 instances, async, defaults. Run T1a and T1b separately, then repeat with `smartShutdownTimeout: 0`.

**T1a: node loses only the control plane.**
1. On the primary's worker: `iptables -I INPUT -s <cp-ip> -j DROP; iptables -I OUTPUT -d <cp-ip> -j DROP`. This also cuts the kubelet and the pod's API traffic, because 10.43.0.1 is DNATed to cp-ip.
2. Hold for 300 s, then heal.
3. *Measure:*
   - whether failover ever starts (`targetPrimary` = pending);
   - whether it completes;
   - liveness probe results (expect OK, logged as "Instance connectivity test succeeded");
   - write success for persistent and same-node writers during the stall;
   - the `-rw` endpoints;
   - after the heal, how the old primary leaves.
4. *Expected on 1.30.1 (t6 suggests):* the node goes NotReady at ~45 s, then label strip and pending failover, which stalls on WAL receivers. No promotion, so no split-brain. Persistent and same-node writers keep succeeding; new connections from other nodes fail.
5. *If a bug is present:* promotion happens without the old primary stopping. Then the result is the same as T1b.

**T1b: as T1a, plus cut replication but keep 8000.**
1. Additionally, inside the old primary pod's netns: `nsenter -t <pg-pid> -n iptables -I INPUT -p tcp --dport 5432 -s 10.42.0.0/16 ! -s <client-pod-ips> -j REJECT --reject-with tcp-reset`, and kill the existing walsenders (`SELECT pg_terminate_backend(pid) FROM pg_stat_replication`) or just wait for `tcp_user_timeout` (5 s).
2. Keep `:8000` open both ways so the isolation pinger succeeds.
3. Hold for 300 s.
4. *Expected if the bug is present (my hypothesis for 1.30.1):*
   - a replica takes the expired lease (the old holder cannot renew; 15 s TTL) and is promoted at roughly 45-55 s + 15 s;
   - the old primary is **never** restarted (liveness OK, because the API is unreachable but peers answer);
   - dual-ack window ≈ the whole partition (~240 s) for persistent and same-node writers. LOST and STOLEN rows then grow linearly.
5. *Expected if safe:* the old primary stops within ~30 s of promotion.
6. *Heal phase:* check the old primary's log for "Primary lease preempted, shutting down" against `reconcileOldPrimary` fast/immediate shutdown, and how long it still acknowledges after the heal (feeds T2).

### T2 (P1). Heal-timing sweep: how the old primary exits after it learns it was replaced

*Why:* on lease preemption the manager context is cancelled and `lifecycle.go` calls `TryShuttingDownSmartFast` (smart shutdown up to 180 s), while `reconcileOldPrimary` uses fast or immediate shutdown. Whichever runs first decides the window after heal or resume. No public report exists.

*Procedure:*
1. Use the Coroot-style pod partition, but **allow** kubelet probe traffic (exempt `10.42.<n>.1`) so that only the isolation logic acts.
2. Run variants:
   - (a) heal at 20 s, before the liveness kill and before any failover; expect no failover and no loss;
   - (b) heal at 45 s and at 60 s, after promotion while the old primary is in smart shutdown;
   - (c) also try with `isolationCheck.enabled: false`, so the only exit is lease preemption or `targetPrimary`.
3. *Measure:* time from heal to the old primary's last ack; which log line triggered the shutdown; shutdown mode ("Requesting smart shutdown" vs "fast" vs "immediate").
4. *Expected if the bug is present:* acks continue for up to 180 s after the heal, through the smart shutdown on preemption.
5. *Expected if fixed or correct:* fewer than ~2 s after the heal (fast or immediate via `reconcileOldPrimary`).
6. Also re-run the colleague's freeze test with a duration sweep straddling the thresholds: 10, 20, 35, 50, 70 and 120 s. These are below and above the lease TTL (15 s), the liveness detection (30 s) and the node grace (~45 s). Record the same metrics. The 50 s and 70 s points are where #10423/#10430 and Discussion #9814 predict a stale primary resuming with sessions attached.

### T3 (P1). Node-level partition with a co-located client: stale kube-proxy, and whether PostgreSQL restarts after the kill (#7407, #11354/#11356)

*Why:* this verifies that #11356 in 1.30.1 really stops an isolated, kubelet-restarted primary from coming back, and measures the stale-kube-proxy exposure on new connections.

*Procedure:*
1. Place a writer pod with `nodeName` = the primary's worker, opening **new connections per write** to `cluster-rw` (ClusterIP).
2. Fully partition that worker from all other nodes, including the cp: `iptables -I INPUT/OUTPUT` DROP for every other node IP **and** UDP 8472. Do not block local traffic.
3. Hold for 300 s.
4. *Measure:*
   - whether same-node new connections keep succeeding before the kill (stale DNAT; expected yes, about 30 s);
   - after the liveness kill, whether the container restarts. Logs should show "Primary lease not yet acquired, retrying" and the startup probe failing (1.30.1). On 1.30.0 PostgreSQL would start and accept the local client again;
   - the total acknowledgements from the isolated side after the replacement is promoted.
5. *Expected on 1.30.1:* only the ~30 s before the kill, plus the smart-shutdown sessions (0 if `smartShutdownTimeout: 0`). No acks after the restart.
6. *Bug signal:* any ack whose `pg_postmaster_start_time` is later than the kill time.

### T4 (P2). Mitigation verification matrix, plus the sync-replication loophole

**T4a: run the Coroot partition under each configuration.**
- Configurations:
  - (i) defaults;
  - (ii) `smartShutdownTimeout: 0`;
  - (iii) (ii) plus `failoverDelay: 30`;
  - (iv) `synchronous: {method: any, number: 1, dataDurability: required, failoverQuorum: true}` with default timeouts.
- Report LOST, STOLEN and dual-ack seconds for each.
- *Expected:*
  - (i) ≈ 99 s overlap with hundreds of lost rows;
  - (ii) overlap ≈ promotion time minus kill time (~0-4 s, a race);
  - (iii) 0 s, with only async lag lost;
  - (iv) 0 acknowledged-then-lost.

**T4b: sync loophole (Nikolay's #7407 note; pgsql-hackers).**
1. Under configuration (iv), during the partition have writers on the isolated primary use `SET statement_timeout='3s'`, or have a second session run `pg_cancel_backend()` on backends waiting in `SyncRep`, or have the client drop its TCP connection.
2. PostgreSQL emits "WARNING: canceling wait for synchronous replication ... The transaction has already committed locally".
3. Have a reader on the isolated primary (persistent connection) `SELECT` those rows.
4. *Expected (by PostgreSQL design):* the rows are visible on the isolated primary and later disappear after the rewind. This shows phantom reads and lost writes even with sync replication.
5. Also measure whether CNPG's smart shutdown prolongs the period in which such rows can be read and acted on.
6. Optional: same in a non-partitioned case with the replica's walreceiver stopped.

### T5 (P2). Switchover races with quorum sync (#11114, #11293). Fix PRs are unmerged, so the bug should be live in 1.30.1

*Setup:* `instances: 3`; `synchronous: {method: any, number: 1, dataDurability: required, failoverQuorum: true}`; a high-rate writer (50-200 tx/s per client, 4 clients, with the ledger).

*Procedure:*
1. Make the replica that will be *chosen* slightly behind on receive. Add `tc qdisc add dev eth0 root netem delay 20ms` in that replica's netns (nsenter) so that the other replica acknowledges first. Repeat with the delay on the other replica, because the target is chosen by received LSN.
2. Trigger (a): `kubectl cordon` the primary's node (`setPrimaryOnSchedulableNode`), or `kubectl taint node <n> karpenter.sh/disrupted=:NoSchedule`.
3. Trigger (b): with `primaryUpdateMethod: switchover`, change a restart-requiring parameter such as `max_connections` or `shared_preload_libraries`.
4. Run about 20 iterations of each.
5. *Measure:*
   - client-acknowledged commits missing on the new timeline (ledger);
   - the crash-loop on the third instance ("requested starting point ... is not in this server's history");
   - `pg_waldump --stats=record -r Transaction` on that replica's WAL after the fork point.
6. *Expected if the bug is present:* occasional runs with replica divergence. The key question is whether any **ledger-acknowledged** rows are lost. That settles the dispute between ardentperf and the reporters.
7. *Expected if correct:* divergence only in unacknowledged (in-doubt) commits.

### T6 (P2). Write-path wedge on the primary (#10678, #10591). Confirm there is no failover, then check a forced failover for dual primary

*Procedure:*
1. Put the primary's PGDATA under a dm-delay or dm-flakey target. Or use `fsfreeze -f` on the local-path filesystem (put the PV on its own loop-mounted filesystem first). Or SIGSTOP the postmaster, checkpointer and WAL writer while leaving the walsenders running (the #10591 recipe).
2. Hold for 10 min.
3. *Measure:* whether the operator ever fails over; `/pg/status` results; WAL receiver state on the replicas.
4. *Expected on 1.30.1:* no failover (availability bug). Persistent writers hang without error.
5. Then **kill the kubelet** (SIGSTOP) on that node to force NotReady and failover. Check whether the WAL-receiver gate blocks promotion forever (#10591), or whether promotion happens and the old primary acknowledges the hung commits when unfrozen.
6. *Bug signal:* hung commits return success after unfreeze while another primary exists.

### T7 (P3). False-positive isolation (#11641): availability impact of the probe logic

*Procedure:*
1. With the primary on w1 and replicas on w2 and w3, power off w3 (`echo o > /proc/sysrq-trigger`).
2. At the same time, in the primary pod's netns, drop traffic to `10.43.0.1` and `<cp-ip>:6443` for 40 s. This simulates the API slowness seen with HA control planes.
3. *Expected on 1.30.1 (bug present):* the primary is killed after about 30 s, giving a 20-30 s outage with no failover.
4. *Expected if fixed:* no restart, because w2 is reachable.
5. Repeat with `requestTimeout` and `connectionTimeout` at 5000.

### T8 (P3). Full API-server outage (control plane down)

*Procedure:* `systemctl stop k3s` on the control-plane node for 180 s, with writers running.

*Expected:*
- all liveness probes OK, because peers are reachable;
- no restarts and no failover;
- the lease cannot be renewed (logged as "unverifiable");
- no write loss.

*Bug signals:*
- any primary restart (#7901-class regression);
- after the API returns, a replica taking over the "expired" lease while the primary is healthy. #11350 territory: check that the primary re-renews before any take-over, and that no spurious failover happens.

### T9 (P3). Async lag at the moment of failover (baseline for "by design" loss)

*Procedure:* run the Coroot partition with `smartShutdownTimeout: 0` and `failoverDelay: 0`, once with a heavy write load so that replicas lag (pgbench `-c 32` plus netem 50 ms on the replica links) and once with a light load.

*Purpose:* LOST rows here are the async RPO that maintainers consider acceptable. Report it separately from split-brain loss, so that results from T1-T5 are not over-attributed.

### Suggested order

T1 (both variants) → T2 (heal sweep, including the freeze-duration sweep) → T3 → T4a/T4b → T5 → T6 → T7, T8, T9.

T1b and T2 are the most likely places to show a still-unreported write-loss path in 1.30.1. T3 and T8 confirm the 1.30.1 fixes (#11356, #11350). T5 is the open, client-unverified loss report.

---

## 5. Version and backport facts at a glance

- **Isolation checker:** experimental in 1.26 (annotation); GA and default-on in 1.27.
- **Primary lease:** 1.30.0 (#10627); retry 2 s (#10950).
- **In v1.30.0** (merged to main before the branch; compare = ahead):
  - #10409 (strip primary label during failover);
  - #10445 (defer failover while the pod is Ready);
  - #10509 (`PrimaryStatusCheckFailed` event).
- **In v1.30.1** (backports on `release-1.30` before `2a35abb46`):
  - #11263 `9cc201dd7`
  - #11356 `b5f4e2552`
  - #11274 `36bec8063`
  - #11347 `aefbab839`
  - #11350 `72075f048`
  - #11336 `e4c83490a`
  - #11518 (docs) `4b4ba674e`
- **Not in 1.30.1:**
  - #11148 (no-sync warning, main only);
  - #11283 and #11504 (closed);
  - #11357, #11358 and #11367 (open, "do not backport", target 1.31);
  - #11185 and #11294 (open);
  - #10428 (open).
- **No post-1.30.1 failover fix** has landed on `release-1.30` since the tag. The commits through 2026-10-14 are CI, dependencies, tests and #11617 (backup).
