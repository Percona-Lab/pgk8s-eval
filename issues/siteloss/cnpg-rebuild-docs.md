### Is there an existing issue already for your request/idea?

I searched and could not find one.

### What problem in the existing documentation this issue aims to solve?

After an unplanned failover in a distributed topology, the old primary site cannot rejoin (`requested timeline 2 is not a child of this server's history`), so it must be rebuilt. Following the obvious path (delete the Cluster and PVCs, re-create it with `bootstrap.recovery.source: dr-b` and `replica.primary: dr-b`) fails in the full-recovery job:

```
barman-cloud-check-wal-archive: ERROR: WAL archive check failed for server dr-a: Expected empty archive
```

because the old cluster's WAL (including writes it accepted after returning) is still under `serverName: dr-a`. It worked only after (a) taking a fresh Backup on dr-b, (b) giving the rebuilt cluster a new `serverName` in its plugin parameters (and in every `externalClusters` entry that points at it, on both sites), and (c) on an idle new primary, waiting for or forcing a WAL switch, since the archive-only replica waited at the backup-end segment until `archive_timeout` (5 min). First attempt took ~11 min; with the steps known, 84 s.

### Describe what additions need to be made to the documentation

A "rebuild the former primary site after failover" procedure in the replica-cluster / distributed-topology page: when a new `serverName` (or archive cleanup) is required, which `externalClusters` must be updated, the need for a recent backup of the new primary, and the archive_timeout wait. Also a note that a site returning after unplanned failover starts as primary until its spec is changed.

### Code of Conduct

- [x] I agree to follow this project's Code of Conduct
