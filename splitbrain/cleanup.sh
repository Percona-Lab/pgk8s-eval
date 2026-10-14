#!/bin/bash
# remove SB_* chains / test rules from every pod sandbox netns on this node
for sb in $(k3s crictl pods -q); do P=$(k3s crictl inspectp -o go-template --template '{{.info.pid}}' $sb 2>/dev/null); [[ "$P" =~ ^[0-9]+$ ]] && [ "$P" -gt 1 ] || continue
 N="nsenter -t $P -n"; if $N iptables -S 2>/dev/null | grep -qE "SB_|10.43.0.0/16|dport 5432 -j DROP|sport 5432 -j DROP"; then
  name=$(k3s crictl inspectp -o go-template --template '{{.status.metadata.name}}' $sb); echo "cleaning $name"
  for ch in INPUT OUTPUT; do $N iptables -D $ch -j SB_$ch 2>/dev/null; $N iptables -F SB_$ch 2>/dev/null; $N iptables -X SB_$ch 2>/dev/null; done
  $N iptables -S | grep -E "10.43.0.0/16|5432 -j DROP" | sed 's/^-A/-D/' | while read r; do $N iptables $r; done
 fi; done
