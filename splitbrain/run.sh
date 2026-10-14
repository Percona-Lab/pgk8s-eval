#!/bin/bash
# run.sh NAME KEY(cnpg|pdirect|pbouncer) NODE POD CONTAINER OWN_CIDR "EXTRA" PART_SECONDS DB DBUSER-SIDE(c|p)
cd ~/pgk8s; NAME=$1 KEY=$2 NODE=$3 POD=$4 CT=$5 OWN=$6 EXTRA=$7 SEC=$8 SIDE=$9
OUT=results/sb_$NAME; mkdir -p $OUT; S="ssh -F ssh_config"
TRUNC="truncate sb2 restart identity"
$S pk-cp "source h.sh; if [ $SIDE = c ]; then psqlc -d app -c \"$TRUNC\"; else psqlp -d cluster1 -c \"$TRUNC\"; fi; kubectl -n probe delete pod writers-$NAME --ignore-not-found >/dev/null; sed -e s/NAME/$NAME/ -e s/KEY/$KEY/ > /tmp/w.yaml; kubectl apply -f /tmp/w.yaml >/dev/null; kubectl -n probe wait --for=condition=Ready pod/writers-$NAME --timeout=60s >/dev/null" < sb/writers.yaml.tpl
sleep 20
$S $NODE "nohup bash /root/isolate.sh $POD $CT $SEC $OWN '$EXTRA' > /tmp/iso.log 2>&1 &"; sleep 1
TP=$($S $NODE "head -1 /tmp/iso.log" | awk '{print $1}'); echo "partition at $TP: $($S $NODE head -1 /tmp/iso.log)" | tee $OUT/summary.txt
$S pk-cp "source h.sh; T0=$TP; for i in \$(seq 1 $(( (SEC+120)/10 ))); do sleep 10; s=\$(( (\$(date +%s%3N)-T0)/1000 )); if [ $SIDE = c ]; then echo \"+\${s}s cur=\$(cprim) phase=\\\"\$(kubectl get cluster cluster-example -o jsonpath={.status.phase})\\\" pods=\$(kubectl get pods -l cnpg.io/cluster=cluster-example --no-headers | awk '{print \$1\":\"\$2\":\"\$3\":\"\$4}' | tr '\n' ' ')\"; else echo \"+\${s}s primaries=\$(kubectl -n \$NSP get pods -l postgres-operator.crunchydata.com/role=primary -o name | cut -d/ -f2 | tr '\n' ,) pods=\$(kubectl -n \$NSP get pods --no-headers | grep instance1 | awk '{print \$1\":\"\$2\":\"\$3\":\"\$4}' | tr '\n' ' ')\"; fi; done" > $OUT/status.log
$S $NODE "cat /tmp/iso.log" >> $OUT/summary.txt
$S pk-cp "kubectl -n probe exec writers-$NAME -- bash -c 'pkill -f writer.sh; sleep 1; true'; for i in 1 2 3; do kubectl -n probe exec writers-$NAME -- cat /tmp/c\$i.log > /tmp/sb_c\$i.log; done" ; for i in 1 2 3; do scp -qF ssh_config pk-cp:/tmp/sb_c$i.log $OUT/c$i.log; done
$S pk-cp "source h.sh; if [ $SIDE = c ]; then psqlc -d app -c 'select id||chr(124)||client||chr(124)||ts from sb2'; else psqlp -d cluster1 -c 'select id||chr(124)||client||chr(124)||ts from sb2'; fi" > $OUT/final.txt
python3 sb/analyze_sb.py $OUT $TP | tee -a $OUT/summary.txt
