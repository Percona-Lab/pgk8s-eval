#!/bin/bash
# rebuild_a.sh RUN MODE: rebuild site A as replica of B after a failed rejoin (CNPG: recreate from B backup; Percona: wipe instance PVCs)
cd ~/pgk8s; RUN=$1 MODE=$2; S="ssh -F ssh_config"
cnpg(){ T0=$(date +%s)
 $S pk-b1 "kubectl -n site-b delete backup b-after-failover --ignore-not-found >/dev/null; printf 'apiVersion: postgresql.cnpg.io/v1\\nkind: Backup\\nmetadata: {name: b-after-failover, namespace: site-b}\\nspec: {cluster: {name: dr-b}, method: plugin, pluginConfiguration: {name: barman-cloud.cloudnative-pg.io}}\\n' | kubectl apply -f - >/dev/null; for i in \$(seq 1 60); do [ \"\$(kubectl -n site-b get backup b-after-failover -o jsonpath={.status.phase})\" = completed ] && break; sleep 3; done; echo \"B backup: \$(kubectl -n site-b get backup b-after-failover -o jsonpath={.status.phase}) after \$((\$(date +%s)-$T0))s\""
 $S pk-cp "kubectl -n site-a delete cluster dr-a --wait=true;  kubectl -n site-a delete pvc -l cnpg.io/cluster=dr-a --wait=true; kubectl -n site-a delete job -l cnpg.io/cluster=dr-a" >/dev/null 2>&1
 sed -e "s#RUN#$RUN#" -e 's#bootstrap: {initdb: {database: app, owner: app}}#bootstrap: {recovery: {source: dr-b}}#' -e 's#replica: {self: dr-a, primary: dr-a, source: dr-b}#replica: {self: dr-a, primary: dr-b, source: dr-b}#' -e 's#parameters: {barmanObjectName: store-a}#parameters: {barmanObjectName: store-a, serverName: dr-a2}#' -e 's#barmanObjectName: store-a, serverName: dr-a}#barmanObjectName: store-a, serverName: dr-a2}#' sl/cnpg-a.yaml | $S pk-cp "kubectl apply -f -" >/dev/null
 ( sleep 90; $S pk-b1 'kubectl -n site-b exec $(kubectl -n site-b get cluster dr-b -o jsonpath={.status.currentPrimary}) -c postgres -- psql -XAtq -c "select pg_switch_wal()"' >/dev/null ) &
 $S pk-cp 'for i in $(seq 1 180); do [ "$(kubectl -n site-a get cluster dr-a -o jsonpath={.status.readyInstances})" = 2 ] && break; sleep 5; done; kubectl -n site-a get cluster dr-a --no-headers'
 echo "CNPG site A rebuilt in $(( $(date +%s)-T0 ))s"; }
pct(){ T0=$(date +%s)
 $S pk-cp 'for p in $(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/data=postgres -o name); do n=${p#pod/}; kubectl -n pct-a delete pvc ${n%-0}-pgdata --wait=false; kubectl -n pct-a delete $p --wait=false; done' >/dev/null 2>&1
 sleep 20
 $S pk-cp 'for i in $(seq 1 180); do L=$(kubectl -n pct-a exec $(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/data=postgres -o name | head -1) -c database -- patronictl list -f json 2>/dev/null | python3 -c "import json,sys; print(\" \".join(m[\"Member\"][-6:]+\":\"+m[\"Role\"]+\":\"+m[\"State\"] for m in json.load(sys.stdin)))" 2>/dev/null); echo "$L" | grep -qE "Standby Leader:(streaming|in archive recovery)" && echo "$L" | grep -q "Replica:streaming" && break; sleep 5; done; echo "$L"'
 echo "Percona site A rebuilt in $(( $(date +%s)-T0 ))s"; }
cnpg > results/sl_$RUN/rebuild_cnpg.log 2>&1 & pct > results/sl_$RUN/rebuild_pct.log 2>&1 & wait; cat results/sl_$RUN/rebuild_*.log
