# sl3 — unplanned site loss, archive only (2026-10-14)
Same topology as sl2, but site B is fed only from object storage (CNPG: barman-cloud plugin store per site; Percona: one shared pgBackRest repo). Defaults: archive_timeout CNPG 5 min, Percona 1 min.
Before loss: CNPG B had replayed none of the 62 s of test writes (lag 363 s since last replayed commit); Percona B lag ~50 s.

Results
- RPO: CNPG lost 1252/1252 acked writes (everything since writers started, 63.7 s; bounded by the 5 min archive_timeout). Percona lost 990/1251 (writes from the last 50.5 s; bounded by 1 min archive_timeout).
- Promote -> writable: CNPG 6.7 s, Percona 5.1 s.
- Returning site A (untouched 269 s): CNPG came back primary, accepted 3831 writes. Percona: Patroni restarted both members as replicas; restore_command fetched site B's 00000002.history from the shared repo; startup failed (PANIC "could not locate a valid checkpoint record" / "requested timeline 2 does not contain minimum recovery point ... on timeline 1"). No writes accepted, but site down. Not a designed fence: in sl2 the same site came back as primary.
- Rejoin: both failed exactly as in sl2 (CNPG "requested timeline 2 is not a child", status healthy; Percona start failed).
- Repair with corrected runbooks: Percona wipe instance PVCs -> 57 s. CNPG backup dr-b (8 s) + recreate dr-a with bootstrap.recovery, new serverName dr-a2 -> 84 s total.
- No timeline pollution of the Percona repo this time (site A never promoted).
