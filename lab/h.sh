# helpers sourced on pk-cp
NSP=postgres-operator
pprim(){ kubectl -n $NSP get pods -l postgres-operator.crunchydata.com/cluster=cluster1,postgres-operator.crunchydata.com/role=primary -o name 2>/dev/null | head -1 | cut -d/ -f2; }
cprim(){ kubectl get cluster cluster-example -o jsonpath='{.status.currentPrimary}'; }
psqlp(){ kubectl -n $NSP exec $(pprim) -c database -- psql -XAtq "$@"; }
psqlc(){ kubectl exec $(cprim) -c postgres -- psql -XAtq "$@"; }
