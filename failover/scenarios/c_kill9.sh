P=$(cprim); echo "cnpg primary $P"; kubectl exec $P -c postgres -- bash -c 'kill -9 $(head -1 /var/lib/postgresql/data/pgdata/postmaster.pid)'
for i in $(seq 1 40); do sleep 3; rd=$(kubectl get cluster cluster-example -o jsonpath={.status.readyInstances}); [ "$rd" = 3 ] && [ $i -gt 3 ] && break; done
echo "primary after: $(cprim) at +$(( ($(date +%s%3N)-T)/1000 ))s"; kubectl get pods; kubectl cnpg status cluster-example | sed -n '/Instances status/,/^$/p'
