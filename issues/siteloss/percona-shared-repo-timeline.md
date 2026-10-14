# Returning former primary site archives a new timeline into the shared standby repo and breaks replicas at the surviving site

**Version:** Percona Operator for PostgreSQL 3.1.0, PostgreSQL 18.6, pgBackRest 2.59.1, Patroni 4.1.5

## Setup
Two Kubernetes clusters in different regions. Site A: `PerconaPGCluster` primary, 2 instances. Site B: standby cluster (`standby.enabled: true`, `repoName: repo1`, `host`/`port` of site A for streaming), 2 instances. Both use the same pgBackRest repo in S3 at a third site, as the standby docs describe.

## Steps
1. Power off all site-A nodes at once (unplanned site loss).
2. Promote site B: `standby.enabled: false`. B becomes primary on timeline 2 and archives `00000002.history`.
3. Power site A back on and leave it alone for ~6 minutes.
4. Scale site B from 2 to 3 instances.

## Result
- Site A came back as a primary and accepted writes from clients still pointed at it (5,174 writes in ~6 min). Patroni promoted it, PostgreSQL found `00000002.history` in the shared repo and chose **timeline 3**, then archived `00000003.history` and timeline-3 WAL into the same repo.
- The new site-B replica restored from the repo, chose recovery timeline 3 (the newest in the repo) and looped:
  `FATAL: highest timeline 2 of the primary is behind recovery timeline 3`
- It recovered only after deleting `00000003.history` and `0000000300000000/*` from S3 by hand and restarting the pod.
- When site A was then set to `standby.enabled: true` (following B), both members failed: `requested timeline 3 does not contain minimum recovery point 0/18006180 on timeline 2`. `patronictl reinit` refused (`Cluster has no leader, can not reinitialize`). Only deleting the instance PVCs worked (56 s).

## Expected
A site that has been superseded must not be able to write into the shared repo, and must not change what replicas of the real primary restore. Suggestions:
- Before a member starts as primary, check the repo for a timeline newer than its own; if found, start fenced (read-only) with a condition and Event.
- Refuse `archive-push` from a superseded timeline.
- Bootstrap replicas on the cluster's current timeline rather than `latest`.
- Provide a supported reinit for a standby cluster without a leader.

Related: #1869 (two-primary guard, diverged standby repair). Reproduction scripts and logs: https://github.com/Percona-Lab/pgk8s-eval/tree/main/siteloss and results/siteloss/sl2.
