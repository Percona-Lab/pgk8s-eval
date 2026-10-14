ts(){ echo "+$(( ($(date +%s%3N)-T)/1000 ))s"; }
PA=$(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/data=postgres -o name|head -1|cut -d/ -f2); PB=$(kubectl -n pct-b get pods -l postgres-operator.crunchydata.com/data=postgres -o name|head -1|cut -d/ -f2)
kubectl -n pct-b patch pg drb --type=merge -p '{"spec":{"standby":{"enabled":true,"repoName":"repo1","host":"dra-primary.pct-a.svc.cluster.local","port":5432}}}' >/dev/null; echo "$(ts) drb demotion requested"
kubectl -n pct-a patch pg dra --type=merge -p '{"spec":{"standby":{"enabled":false}}}' >/dev/null; echo "$(ts) dra promotion requested immediately (no wait)"
for i in $(seq 1 300); do r=$(kubectl -n pct-a exec $PA -c database -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = f ] && break; sleep 1; done; echo "$(ts) dra writable (in_recovery=$r)"
for i in $(seq 1 120); do r=$(kubectl -n pct-b exec $PB -c database -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = t ] && break; sleep 1; done; echo "$(ts) drb in recovery=$r"
echo "final LSNs: dra $(kubectl -n pct-a exec $PA -c database -- psql -XAtc 'select pg_current_wal_lsn()' 2>/dev/null)  drb(replay) $(kubectl -n pct-b exec $PB -c database -- psql -XAtc 'select pg_last_wal_replay_lsn()' 2>/dev/null)"
