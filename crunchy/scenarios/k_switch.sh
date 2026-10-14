P=$(kprim); TGT=$(kubectl -n crunchy get pods -l postgres-operator.crunchydata.com/instance-set=instance1,postgres-operator.crunchydata.com/role=replica -o name | head -1 | cut -d/ -f2); TI=${TGT%-0}; echo "primary $P -> $TI"
kubectl -n crunchy patch postgrescluster hippo --type=merge --patch "{\"spec\":{\"patroni\":{\"switchover\":{\"enabled\":true,\"targetInstance\":\"$TI\"}}}}"
kubectl -n crunchy annotate --overwrite postgrescluster hippo postgres-operator.crunchydata.com/trigger-switchover="$(date)"
for i in $(seq 1 40); do sleep 2; np=$(kprim); [ "$np" = "$TGT" ] && break; done; echo "primary now $np at +$(( ($(date +%s%3N)-T)/1000 ))s"
kubectl -n crunchy patch postgrescluster hippo --type=merge --patch '{"spec":{"patroni":{"switchover":{"enabled":false}}}}'
