P=$(pprim); TGT=$(kubectl -n $NSP get pods -l postgres-operator.crunchydata.com/instance-set=instance1,postgres-operator.crunchydata.com/role=replica -o name | head -1 | cut -d/ -f2); TI=${TGT%-0}; echo "primary $P -> target $TI"
kubectl -n $NSP patch pg cluster1 --type=merge --patch "{\"spec\":{\"patroni\":{\"switchover\":{\"enabled\":true,\"targetInstance\":\"$TI\"}}}}"
kubectl annotate --overwrite -n $NSP pg cluster1 postgres-operator.crunchydata.com/trigger-switchover="$(date)"
for i in $(seq 1 40); do sleep 2; np=$(pprim); [ "$np" = "$TGT" ] && break; done; echo "primary now $np at +$(( ($(date +%s%3N)-T)/1000 ))s"
kubectl -n $NSP patch pg cluster1 --type=merge --patch '{"spec":{"patroni":{"switchover":{"enabled":false}}}}'
sleep 15; kubectl -n $NSP exec $np -c database -- patronictl list
