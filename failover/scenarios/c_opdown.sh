kubectl -n cnpg-system scale deploy cnpg-controller-manager --replicas=0; sleep 5; T=$(date +%s%3N); echo "T_EVENT=$T"
P=$(cprim); echo "operator down; deleting primary $P"; kubectl delete pod $P --wait=false
sleep 90; echo "after 90s: currentPrimary=$(cprim)"; kubectl get pods; kubectl get endpoints cluster-example-rw
T2=$(date +%s%3N); echo "T_OPUP=$T2"; kubectl -n cnpg-system scale deploy cnpg-controller-manager --replicas=1
for i in $(seq 1 60); do sleep 3; rd=$(kubectl get cluster cluster-example -o jsonpath={.status.readyInstances}); [ "$rd" = 3 ] && [ $i -gt 5 ] && break; done
echo "after operator up: primary $(cprim), 3 ready at +$(( ($(date +%s%3N)-T2)/1000 ))s after operator start"; kubectl get pods
