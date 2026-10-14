#!/bin/bash
# freeze.sh POD CONTAINER SECONDS : approximate a VM pause - freeze the pod's cgroup and SIGSTOP the k3s agent (kubelet) on this node
POD=$1; CT=$2; SEC=$3
CID=$(k3s crictl ps --name "$CT" --label io.kubernetes.pod.name="$POD" -q | head -1)
PID=$(k3s crictl inspect -o go-template --template '{{.info.pid}}' "$CID")
if ! [[ "$PID" =~ ^[0-9]+$ ]] || [ "$PID" -le 1 ]; then echo "$(date +%s%3N) ABORT bad pid '$PID' for $POD/$CT"; exit 1; fi
CG=$(cut -d: -f3 /proc/$PID/cgroup | head -1); PODCG=/sys/fs/cgroup$(dirname $CG)
echo "$(date +%s%3N) FREEZE pod=$POD cgroup=$PODCG"
echo 1 > $PODCG/cgroup.freeze; K=$(pgrep -f "k3s agent" | head -1); kill -STOP $K
sleep $SEC
kill -CONT $K; echo 0 > $PODCG/cgroup.freeze
echo "$(date +%s%3N) THAW"
