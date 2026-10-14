#!/bin/bash
# $1 = percona|cnpg ; local-socket write attempts on this node's primary every 2s for $2 iterations
for i in $(seq 1 ${2:-120}); do
  t=$(date +%s%3N)
  if [ "$1" = percona ]; then C=$(k3s crictl ps --name database -q | head -1); r=$(timeout 4 k3s crictl exec $C psql -h /tmp/postgres -d cluster1 -XAtc "select pg_is_in_recovery(); insert into sb(src) values ('isolated') returning 'WROTE'" 2>&1 | tr '\n' ' ')
  else C=$(k3s crictl ps --name postgres -q | head -1); r=$(timeout 4 k3s crictl exec $C psql -h /controller/run -d app -XAtc "select pg_is_in_recovery(); insert into sb(src) values ('isolated') returning 'WROTE'" 2>&1 | tr '\n' ' '); fi
  echo "$t cont=${C:0:8} ${r:0:300}"; sleep 2
done
