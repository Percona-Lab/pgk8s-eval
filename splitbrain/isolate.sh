#!/bin/bash
# isolate.sh POD CONTAINER SECONDS OWN_CIDR "EXTRA_BLOCK_IPS"
# Inside the pod netns: allow loopback, client pods on pk-cp (10.42.0.0/24) and the own node CIDR (kubelet probes),
# drop everything else (other nodes' pods = replicas/operators, services incl. API server 10.43.0.1, node IPs).
POD=$1; CT=$2; SEC=$3; OWN=$4; EXTRA=$5
SBX=$(k3s crictl pods --name "^$POD\$" --state ready -q | head -1)
PID=$(k3s crictl inspectp -o go-template --template '{{.info.pid}}' "$SBX")
if ! [[ "$PID" =~ ^[0-9]+$ ]] || [ "$PID" -le 1 ]; then echo "$(date +%s%3N) ABORT bad pid '$PID' for $POD/$CT"; exit 1; fi
echo "$(date +%s%3N) ISOLATE pod=$POD pid=$PID"
N="nsenter -t $PID -n"
for ch in INPUT OUTPUT; do
  if [ $ch = INPUT ]; then d=-s; else d=-d; fi
  $N iptables -N SB_$ch; $N iptables -I $ch -j SB_$ch
  for ip in $EXTRA; do $N iptables -A SB_$ch $d $ip -j DROP; done
  $N iptables -A SB_$ch -i lo -j RETURN 2>/dev/null || true
  $N iptables -A SB_$ch $d 127.0.0.0/8 -j RETURN
  $N iptables -A SB_$ch $d 10.42.0.0/24 -j RETURN
  $N iptables -A SB_$ch $d $OWN -j RETURN
  $N iptables -A SB_$ch -j DROP
done
sleep $SEC
for ch in INPUT OUTPUT; do $N iptables -D $ch -j SB_$ch; $N iptables -F SB_$ch; $N iptables -X SB_$ch; done
echo "$(date +%s%3N) HEAL"
