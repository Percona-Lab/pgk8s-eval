### Is there an existing issue already for your request/idea?

Related: #7268 (closed as stale; same error after a failover). Not found as a feature request.

### What problem is this feature going to solve? Why should it be implemented?

We tested unplanned loss of a whole site with a distributed topology: two k3s clusters in different regions (~20 ms), S3 at a third site, 2 instances per site, CNPG 1.30.1 + barman-cloud 0.15.1. All site-A nodes were powered off at once; after 60 s site B was promoted with `replica.primary: dr-b` (no demotion token is possible when site A is gone). Results:

| | streaming + object store | object store only |
|---|---|---|
| Acked writes lost | 0 of 1,262 | 1,252 of 1,252 (5-min archive_timeout) |
| Promote → writable | 4.5 s | 6.7 s |
| Site A powered back on, untouched | came back as **primary**, accepted 3,193 writes from stale clients, `Cluster in healthy state` | same, 3,831 writes |
| Site A patched to `replica.primary: dr-b` | designated primary crash-loops: `requested timeline 2 is not a child of this server's history` | same |

So after real site loss, the returning site is a second writable primary until someone edits its spec, and after that it cannot rejoin without a rebuild.

### Describe the solution you'd like

1. **Fence on return:** before starting an instance as primary of a cluster whose `replica.source` cluster has archived a newer timeline (visible in the object store), start fenced/read-only and raise a condition. The object store already holds the evidence.
2. **Rewind on demotion:** when a demoted cluster's designated primary has diverged and the new primary is reachable (streaming externalCluster), run pg_rewind as is done for a former primary within a cluster; otherwise report a clear condition.

### Describe alternatives you've considered

Manual runbook: keep site A isolated before it powers on (often impossible if its own control plane comes back first), then rebuild (see the docs issue on "Expected empty archive").

### Additional context

Scripts and logs: https://github.com/Percona-Lab/pgk8s-eval (`siteloss/`, `results/siteloss/`). One run per mode.

### Code of Conduct

- [x] I agree to follow this project's Code of Conduct
