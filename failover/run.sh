#!/bin/bash
# run.sh <name> <probes(comma)> <remote script file>
cd ~/pgk8s; name=$1; probes=$2; scr=$3
T=$(date +%s%3N); echo "T=$T" > results/$name.log
ssh -F ssh_config pk-cp "source h.sh; T=$T; $(cat $scr)" 2>&1 | tee -a results/$name.log
sleep ${WAIT:-10}; bin/fetch.sh
for n in ${probes//,/ }; do echo "== $n" | tee -a results/$name.log; python3 bin/analyze.py results/probe-$n.log $T $((T+${WIN:-240000})) | tee -a results/$name.log; done
