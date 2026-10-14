#!/bin/bash
# dr_run.sh NAME KEYA KEYB "TRUNCATE_CMD" SWITCH_SCRIPT "FINAL_CMD"   (FINAL_CMD prints id|client|ts from the new primary)
cd ~/pgk8s; NAME=$1 KA=$2 KB=$3 TRUNC=$4 SW=$5 FIN=$6; OUT=results/dr_$NAME; mkdir -p $OUT/a $OUT/b; S="ssh -F ssh_config"
$S pk-cp "source h.sh; $TRUNC; for s in a b; do K=\$( [ \$s = a ] && echo $KA || echo $KB ); kubectl -n probe delete pod writers-$NAME-\$s --ignore-not-found >/dev/null; sed -e s/NAME/$NAME-\$s/ -e s/KEY/\$K/ /root/writers.tpl > /tmp/w.yaml; kubectl apply -f /tmp/w.yaml >/dev/null; done; kubectl -n probe wait --for=condition=Ready pod/writers-$NAME-a pod/writers-$NAME-b --timeout=60s >/dev/null"
sleep 25; T=$(date +%s%3N); echo "T=$T" > $OUT/summary.txt
$S pk-cp "source h.sh; T=$T; $(cat $SW)" 2>&1 | tee -a $OUT/summary.txt
sleep 30
$S pk-cp "for s in a b; do kubectl -n probe exec writers-$NAME-\$s -- bash -c 'pkill -f writer.sh; sleep 1; true'; for i in 1 2 3; do kubectl -n probe exec writers-$NAME-\$s -- cat /tmp/c\$i.log > /tmp/dr_\${s}_c\$i.log; done; done"
for s in a b; do for i in 1 2 3; do scp -qF ssh_config pk-cp:/tmp/dr_${s}_c$i.log $OUT/$s/c$i.log; done; done
$S pk-cp "source h.sh; $FIN" > $OUT/final.txt
python3 sb/dr_analyze.py $OUT $T | tee -a $OUT/summary.txt
