#!/bin/bash
# usage: probe.sh URI  -> prints "epoch_ms OK|FAIL server_ip" every ~200ms
while true; do
  t=$(date +%s%3N)
  r=$(PGCONNECT_TIMEOUT=2 timeout 3 psql "$1" -XAtq -c "set statement_timeout=2000; insert into probe(ts) values (clock_timestamp()) returning inet_server_addr()" 2>&1 | tail -1)
  if [[ "$r" =~ ^[0-9]+\. ]]; then echo "$t OK $r"; else echo "$t FAIL ${r:0:220}"; fi
  sleep 0.2
done
