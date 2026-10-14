P=$(cprim); TGT=$(kubectl get pods -l cnpg.io/cluster=cluster-example,cnpg.io/instanceRole=replica -o name | head -1 | cut -d/ -f2); echo "primary $P -> $TGT"
kubectl cnpg promote cluster-example $TGT
for i in $(seq 1 40); do sleep 2; rd=$(kubectl get cluster cluster-example -o jsonpath={.status.readyInstances}); [ "$(cprim)" = "$TGT" ] && [ "$rd" = 3 ] && break; done; echo "primary now $(cprim) at +$(( ($(date +%s%3N)-T)/1000 ))s"
kubectl cnpg status cluster-example | sed -n '/Instances status/,/^$/p'
