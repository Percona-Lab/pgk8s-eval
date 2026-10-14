ts(){ echo "+$(( ($(date +%s%3N)-T)/1000 ))s"; }
kubectl -n site-b patch cluster dr-b --type=merge -p '{"spec":{"replica":{"primary":"dr-a"}}}' >/dev/null; echo "$(ts) dr-b demotion requested"
kubectl -n site-a patch cluster dr-a --type=merge -p '{"spec":{"replica":{"primary":"dr-a","promotionToken":""}}}' >/dev/null; echo "$(ts) dr-a promotion requested WITHOUT token"
for i in $(seq 1 300); do r=$(kubectl -n site-a exec dr-a-1 -c postgres -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = f ] && break; sleep 1; done; echo "$(ts) dr-a writable (in_recovery=$r)"
for i in $(seq 1 60); do t=$(kubectl -n site-b get cluster dr-b -o jsonpath={.status.demotionToken}); [ -n "$t" ] && break; sleep 2; done; echo "$(ts) dr-b demotionToken present: $([ -n "$t" ] && echo yes || echo no)"
