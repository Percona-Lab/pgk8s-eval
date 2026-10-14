P=$(kprim); echo "crunchy primary $P"; kubectl -n crunchy delete pod $P --wait=false
for i in $(seq 1 40); do sleep 3; np=$(kprim); r=$(kubectl -n crunchy get pods -l postgres-operator.crunchydata.com/instance-set=instance1 --no-headers | grep -c "4/4"); [ -n "$np" ] && [ "$np" != "$P" ] && [ -z "$tp" ] && tp=$(( ($(date +%s%3N)-T)/1000 )); [ "$r" = 3 ] && [ -n "$tp" ] && break; done
echo "new primary $np labelled at +${tp}s, all 3 ready at +$(( ($(date +%s%3N)-T)/1000 ))s"
