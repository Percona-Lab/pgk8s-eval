P=$(cprim); echo "cnpg primary $P"; kubectl delete pod $P --wait=false
for i in $(seq 1 80); do sleep 3; np=$(cprim); [ "$np" != "$P" ] && [ -z "$tp" ] && tp=$(( ($(date +%s%3N)-T)/1000 )); rd=$(kubectl get cluster cluster-example -o jsonpath={.status.readyInstances}); [ "$rd" = 3 ] && [ $i -gt 3 ] && break; done
echo "currentPrimary=$np changed at +${tp:-never}s; 3 ready at +$(( ($(date +%s%3N)-T)/1000 ))s"; kubectl cnpg status cluster-example | sed -n '/Instances status/,$p'
