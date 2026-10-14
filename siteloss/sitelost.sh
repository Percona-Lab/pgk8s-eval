#!/bin/bash
# sitelost.sh RUN MODE(stream|archive) [DECIDE_S=60] [B_ONLY_S=300] [PASSIVE_S=300]
# Unplanned loss of site A (all 4 nodes powered off at once), manual promotion of site B, site A returns, rejoin.
cd ~/pgk8s; RUN=$1 MODE=$2 DECIDE=${3:-60} BONLY=${4:-300} PASSIVE=${5:-300}
S="ssh -F ssh_config"; AIP=<site-a-node-ip> BIP=<site-b-node-ip>; OUT=results/sl_$RUN; mkdir -p $OUT; L=$OUT/events.log; : > $L
ev(){ echo "$(date +%s%3N) $*" | tee -a $L; }
CPW=$($S pk-cp "kubectl -n site-a get secret dr-a-app -o jsonpath={.data.password}|base64 -d"); PPW=$($S pk-cp "kubectl -n pct-a get secret dra-pguser-app -o jsonpath={.data.password}|base64 -d")
CPW=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$CPW"); PPW=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$PPW")
$S pk-x "mkdir -p /root/sl/$RUN; pkill -f \"^bash /root/writer\"; cd /root/sl/$RUN; for c in cA1:$CPW@$AIP:31001 cA2:$CPW@$AIP:31001 cB1:$CPW@$BIP:31002 pA1:$PPW@$AIP:31011 pA2:$PPW@$AIP:31011 pB1:$PPW@$BIP:31012; do n=\${c%%:*}; u=\${c#*:}; nohup bash /root/writer.sh \"postgresql://app:\$u/app?connect_timeout=3\" \$n > \$n.log 2>&1 & done; sleep 2; ls"
ev writers_started; sleep 60
lag(){ $S pk-b1 "kubectl -n site-b exec \$(kubectl -n site-b get cluster dr-b -o jsonpath={.status.currentPrimary}) -c postgres -- psql -XAtq -c \"select 'cnpg-B replay_lag='||coalesce(extract(epoch from now()-pg_last_xact_replay_timestamp())::numeric(10,1)::text,'?')||'s receiving='||(select count(*) from pg_stat_wal_receiver)\"; P=\$(kubectl -n pct-b get pods -l postgres-operator.crunchydata.com/cluster=drb,postgres-operator.crunchydata.com/instance-set=instance1 -o name|head -1); for p in \$(kubectl -n pct-b get pods -l postgres-operator.crunchydata.com/cluster=drb,postgres-operator.crunchydata.com/data=postgres -o name); do kubectl -n pct-b exec \$p -c database -- psql -XAtq -c \"select '\$p replay_lag='||coalesce(extract(epoch from now()-pg_last_xact_replay_timestamp())::numeric(10,1)::text,'?')||'s receiving='||(select count(*) from pg_stat_wal_receiver)\"; done" 2>&1 | tee -a $L; }
lag
# ---- site loss: power off all site-A nodes at once
for h in pk-cp pk-w1 pk-w2 pk-w3; do timeout 5 $S $h 'echo 1 > /proc/sys/kernel/sysrq; echo o > /proc/sysrq-trigger' >/dev/null 2>&1 & done; ev SITE_A_LOST; wait
sleep $DECIDE
ev PROMOTE_B
$S pk-b1 "kubectl -n site-b patch cluster dr-b --type=merge -p '{\"spec\":{\"replica\":{\"primary\":\"dr-b\"}}}'; kubectl -n pct-b patch pg drb --type=merge -p '{\"spec\":{\"standby\":{\"enabled\":false}}}'" 2>&1 | tee -a $L
$S pk-b1 'c=0; p=0; for i in $(seq 1 300); do [ $c = 0 ] && [ "$(kubectl -n site-b exec $(kubectl -n site-b get cluster dr-b -o jsonpath={.status.currentPrimary}) -c postgres -- psql -XAtq -c "select pg_is_in_recovery()" 2>/dev/null)" = f ] && { c=1; echo "$(date +%s%3N) CNPG_B_WRITABLE"; }; P=$(kubectl -n pct-b get pods -l postgres-operator.crunchydata.com/cluster=drb,postgres-operator.crunchydata.com/role=primary -o name 2>/dev/null|head -1); [ $p = 0 ] && [ -n "$P" ] && [ "$(kubectl -n pct-b exec $P -c database -- psql -XAtq -c "select pg_is_in_recovery()" 2>/dev/null)" = f ] && { p=1; echo "$(date +%s%3N) PCT_B_WRITABLE"; }; [ $c = 1 ] && [ $p = 1 ] && break; sleep 1; done' | tee -a $L
sleep $BONLY
ev BOOT_SITE_A
python3 - <<'PY'
import sys,json; sys.path.insert(0,'bin'); from linode import api
for i in json.load(open('instances.json')): api('POST',f"/linode/instances/{i['id']}/boot",{})
PY
until $S -o ConnectTimeout=3 pk-cp 'kubectl get nodes >/dev/null 2>&1'; do sleep 3; done; ev SITE_A_K8S_API_UP
# passive window: nobody touches site A; watch what the old primaries do
for i in $(seq 1 $((PASSIVE/15))); do $S pk-cp "echo \"\$(date +%s%3N) A-STATE cnpg: \$(kubectl -n site-a get cluster dr-a -o jsonpath='{.status.phase}/{.status.currentPrimary}' 2>&1 | head -c 120) pods=\$(kubectl -n site-a get pods -l cnpg.io/cluster=dr-a --no-headers 2>/dev/null | awk '{printf \$1\":\"\$3\":\"\$2\" \"}') | pct: \$(kubectl -n pct-a get pg dra -o jsonpath='{.status.state}') pods=\$(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/data=postgres --no-headers -L postgres-operator.crunchydata.com/role 2>/dev/null | awk '{printf \$1\":\"\$3\":\"\$6\" \"}')\"" | tee -a $L; sleep 15; done
# ---- rejoin site A as a replica of B
ev REJOIN_A
if [ $MODE = stream ]; then PSB="{\"enabled\":true,\"repoName\":\"repo1\",\"host\":\"$BIP\",\"port\":31012}"; else PSB='{"enabled":true,"repoName":"repo1"}'; fi
$S pk-cp "kubectl -n site-a patch cluster dr-a --type=merge -p '{\"spec\":{\"replica\":{\"primary\":\"dr-b\"}}}'; kubectl -n pct-a patch pg dra --type=merge -p '{\"spec\":{\"standby\":$PSB}}'" 2>&1 | tee -a $L
for i in $(seq 1 40); do $S pk-cp "echo \"\$(date +%s%3N) A-STATE cnpg: \$(kubectl -n site-a get cluster dr-a -o jsonpath='{.status.phase}/{.status.currentPrimary}' 2>&1|head -c 120) pods=\$(kubectl -n site-a get pods -l cnpg.io/cluster=dr-a --no-headers 2>/dev/null | awk '{printf \$1\":\"\$3\":\"\$2\":\"\$4\" \"}') | pct: \$(kubectl -n pct-a get pg dra -o jsonpath='{.status.state}') pods=\$(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/data=postgres --no-headers -L postgres-operator.crunchydata.com/role 2>/dev/null | awk '{printf \$1\":\"\$3\":\"\$6\":\"\$4\" \"}')\"" | tee -a $L; sleep 15; done
ev STOP_WRITERS; $S pk-x "pkill -f \"^bash /root/writer\""; sleep 2
scp -qF ssh_config "pk-x:/root/sl/$RUN/*.log" $OUT/
# final tables: B (new primary) via pk-x, A (rejoined replicas) via kubectl on every instance
$S pk-b1 'kubectl -n site-b exec $(kubectl -n site-b get cluster dr-b -o jsonpath={.status.currentPrimary}) -c postgres -- psql -XAtq -d app -c "select id,client,ts from sb2"' > $OUT/final_cnpg_B.txt
$S pk-x "psql -XAtq 'postgresql://app:$PPW@$BIP:31012/app' -c 'select id,client,ts from sb2'" > $OUT/final_pct_B.txt
$S pk-cp 'for p in $(kubectl -n site-a get pods -l cnpg.io/cluster=dr-a -o name); do echo "== $p $(kubectl -n site-a exec $p -c postgres -- psql -XAtq -d app -c "select pg_is_in_recovery(), count(*), max(id), (select count(*) from sb2 where client like '"'"'cB%'"'"') from sb2" 2>&1|tail -1)"; done; for p in $(kubectl -n pct-a get pods -l postgres-operator.crunchydata.com/data=postgres -o name); do echo "== $p $(kubectl -n pct-a exec $p -c database -- psql -XAtq -d app -c "select pg_is_in_recovery(), count(*), max(id), (select count(*) from sb2 where client like '"'"'pB%'"'"') from sb2" 2>&1|tail -1)"; done' | tee $OUT/final_A.txt
$S pk-b1 'kubectl -n site-b exec $(kubectl -n site-b get cluster dr-b -o jsonpath={.status.currentPrimary}) -c postgres -- psql -XAtq -d app -c "select count(*), max(id) from sb2"; P=$(kubectl -n pct-b get pods -l postgres-operator.crunchydata.com/cluster=drb,postgres-operator.crunchydata.com/role=primary -o name|head -1); kubectl -n pct-b exec $P -c database -- psql -XAtq -d app -c "select count(*), max(id) from sb2"' | tee $OUT/final_B_counts.txt
python3 sl/analyze.py $OUT | tee $OUT/summary.txt
