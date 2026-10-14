#!/bin/bash
cd ~/pgk8s; S="ssh -F ssh_config"
cnpg_prep(){ # $1 = merge patch json
  $S pk-cp "kubectl patch cluster cluster-example --type=merge -p '$1' >/dev/null; sleep 20; for i in \$(seq 1 60); do [ \"\$(kubectl get cluster cluster-example -o jsonpath={.status.phase})\" = 'Cluster in healthy state' ] && break; sleep 5; done; kubectl cnpg promote cluster-example cluster-example-3 >/dev/null 2>&1; sleep 30; for i in \$(seq 1 60); do [ \"\$(kubectl get cluster cluster-example -o jsonpath={.status.phase})\" = 'Cluster in healthy state' ] && [ \"\$(kubectl get cluster cluster-example -o jsonpath={.status.currentPrimary})\" = cluster-example-3 ] && break; sleep 5; done; kubectl get cluster cluster-example --no-headers; kubectl get cluster cluster-example -o jsonpath='{.spec.smartShutdownTimeout} {.spec.failoverDelay} {.spec.postgresql.synchronous}'; echo"
}
cnpg_prom(){ $S pk-cp "for p in cluster-example-1 cluster-example-2; do kubectl logs \$p -c postgres --since=15m 2>/dev/null | grep 'database system is ready to accept connections' | grep -o '\"ts\":\"[^\"]*' | tail -1 | sed \"s/^/\$p /\"; done" > results/sb_$1/promotion.txt; }
cnpg_prep '{"spec":{"smartShutdownTimeout":0}}'
sb/run.sh cnpg-sst0 cnpg pk-w3 cluster-example-3 postgres 10.42.3.0/24 "10.42.2.16 10.42.1.26" 300 c; cnpg_prom cnpg-sst0
cnpg_prep '{"spec":{"smartShutdownTimeout":0,"failoverDelay":30}}'
sb/run.sh cnpg-sst0-fd30 cnpg pk-w3 cluster-example-3 postgres 10.42.3.0/24 "10.42.2.16 10.42.1.26" 300 c; cnpg_prom cnpg-sst0-fd30
cnpg_prep '{"spec":{"smartShutdownTimeout":180,"failoverDelay":0,"postgresql":{"synchronous":{"method":"any","number":1,"dataDurability":"required","failoverQuorum":true}}}}'
sb/run.sh cnpg-syncquorum cnpg pk-w3 cluster-example-3 postgres 10.42.3.0/24 "10.42.2.16 10.42.1.26" 300 c; cnpg_prom cnpg-syncquorum
# Percona: primary should be txcs on pk-w1; block the Percona operator explicitly (same node CIDR)
$S pk-cp "source h.sh; echo P=\$(pprim)"
sb/run.sh pct-direct pdirect pk-w1 cluster1-instance1-txcs-0 database 10.42.1.0/24 "10.42.1.23" 300 p
$S pk-cp "kubectl -n postgres-operator logs cluster1-instance1-7z2t-0 -c database --since=15m | grep -E 'promoted self|ready to accept connections' ; kubectl -n postgres-operator logs cluster1-instance1-px4v-0 -c database --since=15m | grep -E 'promoted self|ready to accept connections'" > results/sb_pct-direct/promotion.txt 2>&1
echo CHAIN DONE
