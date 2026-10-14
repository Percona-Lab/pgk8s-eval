ts(){ echo "$(( ($(date +%s%3N)-T)/1000 ))s"; }
kubectl -n crunchy delete pgadmin rhino --wait=false >/dev/null 2>&1
CPW=$(kubectl -n crunchy get secret hippo-pguser-hippo -o jsonpath={.data.password}|base64 -d); CV=$(kubectl -n crunchy get secret hippo-pguser-hippo -o jsonpath={.data.verifier}|base64 -d)
kubectl -n postgres-operator create secret generic mig-volume-pguser-hippo --from-literal=password="$CPW" --from-literal=verifier="$CV" >/dev/null
psqlk -d hippo -c "insert into migmark(note) values ('last write before volume migration')"; echo "+$(ts) last write on crunchy (stop writes = downtime starts)"
CRUNCHY_PRIMARY=$(kprim); PVC_NAME=$(kubectl get pod -n crunchy $CRUNCHY_PRIMARY -o jsonpath='{.spec.volumes[?(@.name=="postgres-data")].persistentVolumeClaim.claimName}'); PV_NAME=$(kubectl get pvc -n crunchy $PVC_NAME -o jsonpath='{.spec.volumeName}'); echo "primary $CRUNCHY_PRIMARY pvc $PVC_NAME pv $PV_NAME"
kubectl patch pv $PV_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl patch postgrescluster hippo -n crunchy --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl delete postgrescluster hippo -n crunchy --wait=false; echo "+$(ts) crunchy cluster deleted"
for i in $(seq 1 60); do [ "$(kubectl get pv $PV_NAME -o jsonpath={.status.phase})" = Released ] && break; sleep 2; done; echo "+$(ts) PV $(kubectl get pv $PV_NAME -o jsonpath={.status.phase})"
kubectl patch pv $PV_NAME --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'; kubectl wait pv $PV_NAME --for=jsonpath='{.status.phase}'=Available --timeout=60s; kubectl label pv $PV_NAME percona-pv-migration=migrated
kubectl -n postgres-operator apply -f /root/mig-volume.yaml; echo "+$(ts) percona cluster created"
for i in $(seq 1 120); do P=$(kubectl -n postgres-operator get pods -l postgres-operator.crunchydata.com/cluster=mig-volume,postgres-operator.crunchydata.com/role=primary -o name | head -1); [ -n "$P" ] && r=$(kubectl -n postgres-operator exec $P -c database -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null) && [ "$r" = f ] && break; sleep 2; done; echo "+$(ts) percona writable on $P"
for i in $(seq 1 60); do s=$(kubectl -n postgres-operator get pg mig-volume -o jsonpath={.status.state}); [ "$s" = ready ] && break; sleep 5; done; echo "+$(ts) percona state=$s"
kubectl -n postgres-operator exec $P -c database -- psql -XAt -d hippo -c "select note from migmark order by t desc limit 2" -c "select string_agg(extname, ',' order by extname) from pg_extension" -c "select count(*) from pgbench_accounts"
kubectl -n postgres-operator exec $P -c database -- bash -c 'grep -hE "FATAL|PANIC|ERROR" /pgdata/pg18/log/*.log 2>/dev/null | grep -v STATEMENT | cut -c1-180 | tail -5'
kubectl -n postgres-operator exec -i $P -c database -- bash -s mig-volume-primary "$CPW" < /root/login.sh
