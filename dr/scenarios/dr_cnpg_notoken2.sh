ts(){ echo "+$(( ($(date +%s%3N)-T)/1000 ))s"; }
kubectl -n site-a patch cluster dr-a --type=merge -p '{"spec":{"replica":{"primary":"dr-b"}}}' >/dev/null && echo "$(ts) dr-a demotion requested" || echo "$(ts) dr-a demotion REJECTED"
kubectl -n site-b patch cluster dr-b --type=merge -p '{"spec":{"replica":{"primary":"dr-b"}}}' >/dev/null && echo "$(ts) dr-b promotion requested WITHOUT token" || echo "$(ts) dr-b promotion REJECTED"
for i in $(seq 1 300); do r=$(kubectl -n site-b exec dr-b-1 -c postgres -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = f ] && break; sleep 1; done; echo "$(ts) dr-b writable (in_recovery=$r)"
for i in $(seq 1 60); do r=$(kubectl -n site-a exec dr-a-1 -c postgres -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = t ] && break; sleep 1; done; echo "$(ts) dr-a in recovery=$r"
