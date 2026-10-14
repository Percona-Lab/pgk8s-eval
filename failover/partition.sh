#!/bin/bash
# full isolation from other cluster nodes for $1 seconds (ssh from outside keeps working)
for ip in <node-public-ip> 192.168.192.10 <node-public-ip> 192.168.192.68 <node-public-ip> 192.168.145.57; do for c in INPUT FORWARD; do iptables -I $c -s $ip -j DROP; done; for c in OUTPUT FORWARD; do iptables -I $c -d $ip -j DROP; done; done
sleep $1
for ip in <node-public-ip> 192.168.192.10 <node-public-ip> 192.168.192.68 <node-public-ip> 192.168.145.57; do for c in INPUT FORWARD; do iptables -D $c -s $ip -j DROP; done; for c in OUTPUT FORWARD; do iptables -D $c -d $ip -j DROP; done; done
