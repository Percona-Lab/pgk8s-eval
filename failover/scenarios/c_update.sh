kubectl patch cluster cluster-example --type=merge -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:18.6-standard-trixie"}}'
sleep 20; for i in $(seq 1 100); do sleep 5; ph=$(kubectl get cluster cluster-example -o jsonpath={.status.phase}); n=$(kubectl get pods -l cnpg.io/cluster=cluster-example -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | grep -c standard); [ "$ph" = "Cluster in healthy state" ] && [ "$n" = 3 ] && break; done
echo "rolled 3 instances in $(( ($(date +%s%3N)-T)/1000 ))s phase=$ph primary=$(cprim)"
