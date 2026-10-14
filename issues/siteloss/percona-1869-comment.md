Additional evidence from an **unplanned site-loss** test (two k3s clusters in different regions, ~20 ms apart; S3 at a third site; 2 instances per site; Percona Operator 3.1.0).

All site-A nodes were powered off at once; after 60 s site B was promoted (`standby.enabled: false`). Site A was powered back on and left alone, then set to `standby.enabled: true` (following B).

| | streaming + repo | repo only |
|---|---|---|
| Acked writes lost | 0 of 1,261 | 990 of 1,251 (last 50 s, 1-min archive_timeout) |
| Promote → writable | 5.2 s | 5.1 s |
| Site A on return, untouched | **second primary**, 5,174 writes from stale clients over ~6 min | both members crash-looped after fetching B's timeline from the shared repo |
| Site A set to follow B | both members `start failed` (`requested timeline 3 does not contain minimum recovery point`) | same |
| `patronictl reinit` | refused: `Cluster has no leader, can not reinitialize` | — |
| Repair | delete instance PVCs: 56 s | 57 s |

So nothing fences a returning former primary site, and there is no supported way to rejoin it short of deleting volumes. The shared repo already holds a newer timeline that could be used to fence it. The repo side effect is filed separately: #1871.

Scripts and logs: https://github.com/Percona-Lab/pgk8s-eval/tree/main/siteloss
