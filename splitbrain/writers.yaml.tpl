apiVersion: v1
kind: Pod
metadata: {name: writers-NAME, namespace: probe}
spec:
  restartPolicy: Never
  nodeSelector: {kubernetes.io/hostname: pk-cp}
  tolerations: [{key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}]
  containers:
  - name: w
    image: docker.io/percona/percona-distribution-postgresql:18.6.1-1
    command: [bash, -c, 'for i in 1 2 3; do bash /s/writer.sh "$URI" c$i > /tmp/c$i.log 2>&1 & done; sleep infinity']
    env: [{name: URI, valueFrom: {secretKeyRef: {name: uris, key: KEY}}}]
    volumeMounts: [{name: s, mountPath: /s}]
  volumes: [{name: s, configMap: {name: writer}}]
