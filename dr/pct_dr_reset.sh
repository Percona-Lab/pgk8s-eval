# run on pk-cp: recreate Percona DR pair dra (pct-a) + drb standby (pct-b) on a fresh repo path $1
RP=$1
for c in a b; do kubectl -n pct-$c delete pg dr$c --wait=true >/dev/null 2>&1; kubectl -n pct-$c delete pvc --all --wait=false >/dev/null 2>&1; done
kubectl -n pct-b delete secret drb-pguser-app --ignore-not-found >/dev/null; sleep 15
for c in a b; do sed "s#/pgbackrest/dr/repo1#$RP#" /root/pct-dr$c.yaml > /tmp/pct-dr$c.yaml; done
kubectl apply -f /tmp/pct-dra.yaml >/dev/null; for i in $(seq 1 90); do [ "$(kubectl -n pct-a get pg dra -o jsonpath={.status.state})" = ready ] && break; sleep 5; done
P=$(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/role=primary -o name|head -1); kubectl -n pct-a exec $P -c database -- psql -XAtq -d app -c 'create table sb2(id bigserial primary key, client text, ts timestamptz default clock_timestamp()); alter table sb2 owner to app'
kubectl -n pct-a delete perconapgbackup --all >/dev/null 2>&1; printf 'apiVersion: pgv2.percona.com/v2\nkind: PerconaPGBackup\nmetadata: {name: dra-full, namespace: pct-a}\nspec: {pgCluster: dra, repoName: repo1, options: ["--type=full","--start-fast"]}\n' | kubectl apply -f - >/dev/null; for i in $(seq 1 60); do [ "$(kubectl -n pct-a get pg-backup dra-full -o jsonpath={.status.state})" = Succeeded ] && break; sleep 5; done
PW=$(kubectl -n pct-a get secret dra-pguser-app -o jsonpath={.data.password}|base64 -d); V=$(kubectl -n pct-a get secret dra-pguser-app -o jsonpath={.data.verifier}|base64 -d); kubectl -n pct-b create secret generic drb-pguser-app --from-literal=password="$PW" --from-literal=verifier="$V" >/dev/null
if [ "$2" = streaming ]; then for x in dra-cluster-cert dra-replication-cert; do kubectl -n pct-a get secret $x -o json | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({'apiVersion':'v1','kind':'Secret','type':d['type'],'metadata':{'name':d['metadata']['name']},'data':d['data']}))" | kubectl -n pct-b apply -f - >/dev/null; done
python3 - /tmp/pct-drb.yaml <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("standby: {enabled: true, repoName: repo1}","standby: {enabled: true, repoName: repo1, host: dra-primary.pct-a.svc.cluster.local, port: 5432}\n  secrets: {customTLSSecret: {name: dra-cluster-cert}, customReplicationTLSSecret: {name: dra-replication-cert}}")
open(p,'w').write(s)
PY
fi
kubectl apply -f /tmp/pct-drb.yaml >/dev/null; for i in $(seq 1 90); do [ "$(kubectl -n pct-b get pg drb -o jsonpath={.status.state})" = ready ] && break; sleep 5; done
UA=$(kubectl -n pct-a get secret dra-pguser-app -o jsonpath={.data.uri}|base64 -d); UB=$(echo "$UA" | sed 's#dra-primary.pct-a.svc#drb-primary.pct-b.svc#')
kubectl -n probe get secret uris -o json | python3 -c "
import json,sys,base64; d=json.load(sys.stdin); d['data']['pdra']=base64.b64encode(sys.argv[1].encode()).decode(); d['data']['pdrb']=base64.b64encode(sys.argv[2].encode()).decode()
[d['metadata'].pop(k,None) for k in ('resourceVersion','uid','creationTimestamp','managedFields')]; print(json.dumps(d))" "$UA" "$UB" | kubectl apply -f - >/dev/null
echo "dra=$(kubectl -n pct-a get pg dra -o jsonpath={.status.state}) drb=$(kubectl -n pct-b get pg drb -o jsonpath={.status.state}) uri-host=$(echo $UA | sed 's#.*@##')"
