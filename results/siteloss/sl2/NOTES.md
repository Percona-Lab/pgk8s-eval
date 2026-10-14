# sl2 — unplanned site loss, streaming + archive (2026-10-14)
Topology: site A = k3s us-southeast (pk-cp,w1-3), site B = k3s us-east (pk-b1..b3), object storage + clients = pk-x us-central. A<->B RTT ~20 ms.
Each operator: 2 instances per site, B = replica/standby cluster streaming from A over NodePort + archive. Writers on pk-x: 2 persistent clients -> A, 1 -> B (read-only until promotion), ~8 writes/s each.
Fault: sysrq power-off of all 4 site-A VMs at once (watchdog off). Promote B after 62 s. Site A booted after +367 s; untouched for 357 s; then rejoin commanded.

Results
- RPO: CNPG 0/1262 lost, Percona 0/1261 lost (B replay lag ~0.1 s before loss).
- Promote -> writable: CNPG 4.5 s, Percona 5.2 s (first acked write 3.8 s / 4.1 s).
- Returning site A: both old primaries started as primaries and accepted writes from stale clients: CNPG 3193, Percona 5174 (until rejoin cmd). Neither operator fenced or warned. CNPG status "Cluster in healthy state". None of these writes reached B.
- Percona zombie promoted to timeline 3 and archived it into the SHARED pgBackRest repo (00000003.history + TL3 WAL). Effect on surviving site B: a new B replica (scale 2->3) restored from repo picked recovery TL3 and looped "highest timeline 2 of the primary is behind recovery timeline 3". Fixed only by deleting TL3 files from S3 by hand + restarting the pod.
- CNPG zombie archived to its own path (sl2/dr-a) -> B unaffected; B scaled 2->3 fine.
- Rejoin (patch A to follow B): both FAILED automatically.
  - CNPG dr-a-1 crash-loop "requested timeline 2 is not a child of this server's history" (no pg_rewind on demotion without token); cluster status still "Cluster in healthy state"/Ready=True.
  - Percona both members "start failed": "requested timeline 3 does not contain minimum recovery point ... on timeline 2"; patronictl reinit refused ("Cluster has no leader").
- Repair:
  - Percona: delete instance PVCs+pods -> rebuilt from repo + streaming from B in 56 s (after repo cleanup).
  - CNPG: backup of dr-b (11 s); recreate dr-a with bootstrap.recovery from dr-b -> FAILED "Expected empty archive" (old dr-a WAL in store); needed new serverName (dr-a2); then waited for WAL segment to be archived on idle B (archive-only externalCluster, archive_timeout 5 min) -> forced pg_switch_wal; ready 30 s later.
