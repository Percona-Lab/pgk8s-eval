#!/bin/bash
cd ~/pgk8s; S="ssh -F ssh_config"
cnpg_w3(){ $S pk-cp "kubectl cnpg promote cluster-example cluster-example-3 >/dev/null 2>&1; sleep 30; for i in \$(seq 1 60); do [ \"\$(kubectl get cluster cluster-example -o jsonpath={.status.phase})\" = 'Cluster in healthy state' ] && [ \"\$(kubectl get cluster cluster-example -o jsonpath={.status.currentPrimary})\" = cluster-example-3 ] && break; sleep 5; done; kubectl get cluster cluster-example --no-headers"; }
cnpg_repl(){ $S pk-cp "kubectl get pods -l cnpg.io/cluster=cluster-example,cnpg.io/instanceRole=replica -o jsonpath='{.items[*].status.podIP}'"; }
pct_prim(){ $S pk-cp "kubectl -n postgres-operator get pods -l postgres-operator.crunchydata.com/role=primary -o jsonpath='{.items[0].metadata.name} {.items[0].spec.nodeName} {.items[0].status.podIP}'"; }
pct_repl(){ $S pk-cp "kubectl -n postgres-operator get pods -l postgres-operator.crunchydata.com/role=replica,postgres-operator.crunchydata.com/instance-set=instance1 -o jsonpath='{.items[*].status.podIP}'"; }
pct_heal(){ for h in pk-w1 pk-w2 pk-w3; do $S $h bash /root/cleanup.sh; done; $S pk-cp "kubectl -n postgres-operator get pods --no-headers | grep instance1 | grep -v ' 6/6 ' | awk '{print \$1}' | xargs -r kubectl -n postgres-operator delete pod --wait=false"; sleep 90; }
cidr(){ case $1 in pk-w1) echo 10.42.1.0/24;; pk-w2) echo 10.42.2.0/24;; pk-w3) echo 10.42.3.0/24;; esac; }
# reset CNPG to defaults
$S pk-cp "kubectl patch cluster cluster-example --type=merge -p '{\"spec\":{\"smartShutdownTimeout\":180,\"failoverDelay\":0,\"postgresql\":{\"synchronous\":null}}}' >/dev/null; sleep 30"
# 1 Percona via pgBouncer
read P N IP <<< "$(pct_prim)"; echo "pct primary $P $N"
sb/run_fault.sh pct-bouncer pbouncer $N p 420 "bash /root/isolate.sh $P database 300 $(cidr $N) '10.42.1.23 10.42.2.16'"; pct_heal
# 2 CNPG blind spot
cnpg_w3; R=$(cnpg_repl); echo "cnpg replicas $R"
sb/run_fault.sh cnpg-blindspot cnpg pk-w3 c 420 "bash /root/blindspot.sh cluster-example-3 postgres 300 '$R'"; for h in pk-w3; do $S $h bash /root/cleanup.sh; done
# 3 Percona blind spot
read P N IP <<< "$(pct_prim)"; R=$(pct_repl); echo "pct primary $P $N replicas $R"
sb/run_fault.sh pct-blindspot pdirect $N p 420 "bash /root/blindspot.sh $P database 300 '$R'"; pct_heal
# 4 CNPG VM-pause approximations
cnpg_w3; sb/run_fault.sh cnpg-freeze30 cnpg pk-w3 c 240 "bash /root/freeze.sh cluster-example-3 postgres 30"
cnpg_w3; sb/run_fault.sh cnpg-freeze120 cnpg pk-w3 c 360 "bash /root/freeze.sh cluster-example-3 postgres 120"
# 5 Percona VM pause
read P N IP <<< "$(pct_prim)"; echo "pct primary $P $N"
sb/run_fault.sh pct-freeze120 pdirect $N p 360 "bash /root/freeze.sh $P database 120"; pct_heal
echo CHAIN2 DONE
