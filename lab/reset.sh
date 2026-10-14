#!/bin/bash
H=$1
hostnamectl set-hostname $H
sed -i '/^127.0.1.1/d' /etc/hosts; echo "127.0.1.1 $H" >> /etc/hosts
for u in k3s-uninstall.sh k3s-agent-uninstall.sh; do [ -x /usr/local/bin/$u ] && /usr/local/bin/$u >/dev/null 2>&1; done
hostname; ls /usr/local/bin | grep -c k3s
