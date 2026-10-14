#!/bin/bash
# blindspot.sh POD CONTAINER SECONDS "REPLICA_IPS"
POD=$1; CT=$2; SEC=$3; REPL=$4
SBX=$(k3s crictl pods --name "^$POD\$" --state ready -q | head -1)
PID=$(k3s crictl inspectp -o go-template --template '{{.info.pid}}' "$SBX")
if ! [[ "$PID" =~ ^[0-9]+$ ]] || [ "$PID" -le 1 ]; then echo "$(date +%s%3N) ABORT bad pid"; exit 1; fi
echo "$(date +%s%3N) BLINDSPOT pod=$POD pid=$PID"
N="nsenter -t $PID -n"
# host: kubelet/agent loses API server
for ip in 192.168.192.10 <node-public-ip>; do iptables -I OUTPUT -d $ip -p tcp --dport 6443 -j DROP; done
# pod: no API server, no 5432 with replicas (walreceivers break), 8000 stays open
$N iptables -I OUTPUT -d 10.43.0.0/16 -j DROP
for r in $REPL; do $N iptables -I INPUT -s $r -p tcp --dport 5432 -j DROP; $N iptables -I OUTPUT -d $r -p tcp --sport 5432 -j DROP; done
sleep $SEC
for ip in 192.168.192.10 <node-public-ip>; do iptables -D OUTPUT -d $ip -p tcp --dport 6443 -j DROP; done
$N iptables -D OUTPUT -d 10.43.0.0/16 -j DROP
for r in $REPL; do $N iptables -D INPUT -s $r -p tcp --dport 5432 -j DROP; $N iptables -D OUTPUT -d $r -p tcp --sport 5432 -j DROP; done
echo "$(date +%s%3N) HEAL"
