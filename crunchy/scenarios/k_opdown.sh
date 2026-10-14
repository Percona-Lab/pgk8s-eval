kubectl -n pgo scale deploy pgo --replicas=0; sleep 5; T=$(date +%s%3N); echo "T_EVENT=$T"
P=$(kprim); echo "operator down; deleting primary $P"; kubectl -n crunchy delete pod $P --wait=false
for i in $(seq 1 30); do sleep 3; np=$(kprim); [ -n "$np" ] && [ "$np" != "$P" ] && break; done; echo "primary now ${np:-NONE} at +$(( ($(date +%s%3N)-T)/1000 ))s"; sleep 20
kubectl -n crunchy get pods | grep instance1; kubectl -n pgo scale deploy pgo --replicas=1
