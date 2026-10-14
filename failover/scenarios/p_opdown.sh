kubectl -n $NSP scale deploy percona-postgresql-operator --replicas=0; sleep 5; T=$(date +%s%3N); echo "T_EVENT=$T"
P=$(pprim); echo "operator down; deleting primary $P"; kubectl -n $NSP delete pod $P --wait=false
for i in $(seq 1 30); do sleep 3; np=$(pprim); [ -n "$np" ] && [ "$np" != "$P" ] && break; done; echo "primary now ${np:-NONE} at +$(( ($(date +%s%3N)-T)/1000 ))s"; sleep 20
kubectl -n $NSP get pods | grep -E "instance1|operator"; kubectl -n $NSP exec $np -c database -- patronictl list
kubectl -n $NSP scale deploy percona-postgresql-operator --replicas=1
