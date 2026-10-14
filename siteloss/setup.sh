#!/bin/bash
# setup.sh RUN MODE(stream|archive): recreate CNPG dr-a/dr-b and Percona dra/drb across site A (pk-cp) and site B (pk-b1)
cd ~/pgk8s; RUN=$1 MODE=$2; S="ssh -F ssh_config"; AIP=<site-a-node-ip>
for h in "pk-cp site-a pct-a dr-a dra" "pk-b1 site-b pct-b dr-b drb"; do set -- $h
  $S $1 "kubectl -n $2 delete cluster $4 --ignore-not-found --wait=true; kubectl -n $3 delete pg $5 --ignore-not-found --wait=true; kubectl -n $3 delete perconapgbackup --all; kubectl -n $2 delete backup --all; sleep 5; kubectl -n $2 delete pvc --all; kubectl -n $3 delete pvc --all; kubectl -n $3 delete secret $5-pguser-app dra-cluster-cert dra-replication-cert --ignore-not-found; kubectl -n $2 delete secret dra-repl dra-ca --ignore-not-found" >/dev/null 2>&1 &
done; wait
for f in cnpg-a pct-a; do sed -e "s#RUN#$RUN#" -e '/#STANDBY/d' sl/$f.yaml; echo ---; done | $S pk-cp "kubectl apply -f -" || exit 1
$S pk-cp 'for i in $(seq 1 120); do a=$(kubectl -n site-a get cluster dr-a -o jsonpath={.status.readyInstances}); b=$(kubectl -n pct-a get pg dra -o jsonpath={.status.state}); [ "$a" = 2 ] && [ "$b" = ready ] && break; sleep 5; done; echo "A: cnpg ready=$a pct=$b"
 SQL="create table sb2(id bigserial primary key, client text, ts timestamptz default clock_timestamp()); alter table sb2 owner to app"
 kubectl -n site-a exec $(kubectl -n site-a get cluster dr-a -o jsonpath={.status.currentPrimary}) -c postgres -- psql -XAtq -d app -c "$SQL"
 P=$(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/cluster=dra,postgres-operator.crunchydata.com/role=primary -o name|head -1); kubectl -n pct-a exec $P -c database -- psql -XAtq -d app -c "$SQL"
 printf "apiVersion: postgresql.cnpg.io/v1\nkind: Backup\nmetadata: {name: base, namespace: site-a}\nspec: {cluster: {name: dr-a}, method: plugin, pluginConfiguration: {name: barman-cloud.cloudnative-pg.io}}\n---\napiVersion: pgv2.percona.com/v2\nkind: PerconaPGBackup\nmetadata: {name: dra-full, namespace: pct-a}\nspec: {pgCluster: dra, repoName: repo1, options: [\"--type=full\",\"--start-fast\"]}\n" | kubectl apply -f - >/dev/null
 for i in $(seq 1 90); do a=$(kubectl -n site-a get backup base -o jsonpath={.status.phase}); b=$(kubectl -n pct-a get pg-backup dra-full -o jsonpath={.status.state}); [ "$a" = completed ] && [ "$b" = Succeeded ] && break; sleep 5; done; echo "backups: cnpg=$a pct=$b"'
sl/cpsec.sh pk-cp pct-a dra-pguser-app pk-b1 pct-b drb-pguser-app >/dev/null
SB='  standby: {enabled: true, repoName: repo1}'; ST=''
if [ $MODE = stream ]; then
  sl/cpsec.sh pk-cp site-a dr-a-replication pk-b1 site-b dra-repl >/dev/null; sl/cpsec.sh pk-cp site-a dr-a-ca pk-b1 site-b dra-ca >/dev/null
  sl/cpsec.sh pk-cp pct-a dra-cluster-cert pk-b1 pct-b >/dev/null; sl/cpsec.sh pk-cp pct-a dra-replication-cert pk-b1 pct-b >/dev/null
  SB="  standby: {enabled: true, repoName: repo1, host: $AIP, port: 31011}\n  secrets: {customTLSSecret: {name: dra-cluster-cert}, customReplicationTLSSecret: {name: dra-replication-cert}}"
  ST="    connectionParameters: {host: $AIP, port: \"31001\", user: streaming_replica, sslmode: verify-ca, dbname: postgres}\n    sslKey: {name: dra-repl, key: tls.key}\n    sslCert: {name: dra-repl, key: tls.crt}\n    sslRootCert: {name: dra-ca, key: ca.crt}"
fi
{ sed -e "s#RUN#$RUN#" -e "s|#STREAM_A|$ST|" sl/cnpg-b.yaml; echo ---; sed -e "s#RUN#$RUN#" -e "s|#STANDBY|$SB|" sl/pct-b.yaml; } | tee sl/last-b.yaml | $S pk-b1 "kubectl apply -f -" || exit 1
$S pk-b1 'for i in $(seq 1 150); do a=$(kubectl -n site-b get cluster dr-b -o jsonpath={.status.readyInstances}); b=$(kubectl -n pct-b get pg drb -o jsonpath={.status.state}); [ "$a" = 2 ] && [ "$b" = ready ] && break; sleep 5; done; echo "B: cnpg ready=$a pct=$b"; kubectl -n site-b get cluster; kubectl -n pct-b get pods -L postgres-operator.crunchydata.com/role'
