ts(){ echo "$(( ($(date +%s%3N)-T)/1000 ))s"; }
sp(){ kubectl -n postgres-operator get pods -l postgres-operator.crunchydata.com/cluster=mig-standby,postgres-operator.crunchydata.com/role=primary -o name 2>/dev/null | head -1; }
SP=$(kubectl -n postgres-operator get pods -l postgres-operator.crunchydata.com/cluster=mig-standby,postgres-operator.crunchydata.com/role=standby-leader -o name | head -1); [ -z "$SP" ] && SP=$(sp); echo "percona standby leader $SP"
psqlk -d hippo -c "insert into migmark(note) values ('last write before cutover')"
kubectl -n crunchy patch postgrescluster hippo --type=merge -p '{"spec":{"standby":{"enabled":true,"repoName":"repo2"}}}'; echo "+$(ts) crunchy patched to standby"
for i in $(seq 1 60); do r=$(psqlk -c "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = t ] && break; sleep 1; done; echo "+$(ts) crunchy in recovery=$r"
kubectl -n crunchy patch postgrescluster hippo --type=merge -p '{"spec":{"shutdown":true}}'; echo "+$(ts) crunchy shutdown requested"
p=""; for i in $(seq 1 60); do l=$(kubectl -n postgres-operator exec $SP -c database -- psql -XAtc "select pg_last_wal_replay_lsn()"); [ "$l" = "$p" ] && break; p=$l; sleep 3; done; echo "+$(ts) percona replay LSN stable at $l"
kubectl -n postgres-operator patch pg mig-standby --type=merge -p '{"spec":{"standby":{"enabled":false}}}'; echo "+$(ts) percona promote requested"
for i in $(seq 1 120); do P=$(sp); r=$(kubectl -n postgres-operator exec ${P:-$SP} -c database -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = f ] && break; sleep 1; done; echo "+$(ts) percona writable (pg_is_in_recovery=$r) on $P"
kubectl -n postgres-operator exec $P -c database -- psql -XAt -d hippo -c "insert into migmark(note) values ('first write on percona')" -c "select note from migmark order by t desc limit 3"
for i in $(seq 1 60); do s=$(kubectl -n postgres-operator get pg mig-standby -o jsonpath={.status.state}); [ "$s" = ready ] && break; sleep 5; done; echo "+$(ts) percona state=$s"
