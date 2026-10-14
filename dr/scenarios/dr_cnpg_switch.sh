ts(){ echo "+$(( ($(date +%s%3N)-T)/1000 ))s"; }
ua=$(kubectl -n site-a get pod dr-a-1 -o jsonpath={.metadata.uid}); pa=$(kubectl -n site-a get pvc dr-a-1 -o jsonpath={.metadata.uid})
kubectl -n site-a patch cluster dr-a --type=merge -p '{"spec":{"replica":{"primary":"dr-b"}}}' >/dev/null; echo "$(ts) dr-a demotion requested (replica.primary=dr-b)"
for i in $(seq 1 120); do TOK=$(kubectl -n site-a get cluster dr-a -o jsonpath={.status.demotionToken}); [ -n "$TOK" ] && break; sleep 1; done; echo "$(ts) demotionToken available (${#TOK} chars)"
kubectl -n site-b patch cluster dr-b --type=merge -p "{\"spec\":{\"replica\":{\"primary\":\"dr-b\",\"promotionToken\":\"$TOK\"}}}" >/dev/null; echo "$(ts) dr-b promotion requested with token"
for i in $(seq 1 300); do r=$(kubectl -n site-b exec dr-b-1 -c postgres -- psql -XAtc "select pg_is_in_recovery()" 2>/dev/null); [ "$r" = f ] && break; sleep 1; done; echo "$(ts) dr-b writable (in_recovery=$r)"
for i in $(seq 1 60); do ph=$(kubectl -n site-a get cluster dr-a -o jsonpath={.status.phase}); [ "$ph" = "Cluster in healthy state" ] && break; sleep 3; done; echo "$(ts) dr-a phase: $ph"
sleep 20; echo "dr-a pod uid unchanged: $([ "$ua" = "$(kubectl -n site-a get pod dr-a-1 -o jsonpath={.metadata.uid})" ] && echo yes || echo no-restarted); PVC unchanged: $([ "$pa" = "$(kubectl -n site-a get pvc dr-a-1 -o jsonpath={.metadata.uid})" ] && echo yes || echo NO-reclone)"
echo "dr-a in recovery (now replica): $(kubectl -n site-a exec dr-a-1 -c postgres -- psql -XAtc 'select pg_is_in_recovery()')"
