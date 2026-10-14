#!/bin/bash
# cpsec.sh SRCHOST NS SECRET DSTHOST DSTNS [NEWNAME] : copy a secret between clusters
cd ~/pgk8s; ssh -F ssh_config $1 "kubectl -n $2 get secret $3 -o json" | python3 -c "
import json,sys; d=json.load(sys.stdin); n=sys.argv[1] or d['metadata']['name']
print(json.dumps({'apiVersion':'v1','kind':'Secret','type':d['type'],'metadata':{'name':n},'data':d['data']}))" "$6" | ssh -F ssh_config $4 "kubectl -n $5 apply -f -"
