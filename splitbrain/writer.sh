#!/bin/bash
# persistent-connection writer: $1=URI $2=client id. Logs "client_ms ACK id|server_ip|server_ts" or errors.
URI=$1; CID=$2
while true; do
  { while true; do echo "insert into sb2(client) values ('$CID') returning id, inet_server_addr(), ts;"; sleep 0.1; done; } \
   | PGCONNECT_TIMEOUT=3 stdbuf -oL -eL psql "$URI" -XAtq -v ON_ERROR_STOP=0 2>&1 \
   | while IFS= read -r l; do t=$(date +%s%3N); if [[ "$l" =~ ^[0-9]+\| ]]; then echo "$t ACK $l"; else echo "$t ERR ${l:0:160}"; fi; done
  echo "$(date +%s%3N) RECONNECT"; sleep 0.5
done
