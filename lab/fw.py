import sys,os,json
sys.path.insert(0,os.path.dirname(__file__))
from linode import api
inst=json.load(open(os.path.expanduser('~/pgk8s/instances.json')))
priv=[i['ips'][1]+'/32' for i in inst]; pubs=[i['ips'][0]+'/32' for i in inst]
r=api('POST','/networking/firewalls',{'label':'pgk8s-fw','tags':['pgk8s'],'rules':{'inbound_policy':'DROP','outbound_policy':'ACCEPT','inbound':[
 {'action':'ACCEPT','protocol':'TCP','ports':'22','addresses':{'ipv4':['0.0.0.0/0']},'label':'ssh'},
 {'action':'ACCEPT','protocol':'TCP','addresses':{'ipv4':priv+pubs},'label':'tcp-cluster'},
 {'action':'ACCEPT','protocol':'UDP','addresses':{'ipv4':priv+pubs},'label':'udp-cluster'},
 {'action':'ACCEPT','protocol':'ICMP','addresses':{'ipv4':['0.0.0.0/0']},'label':'icmp'}]},
 'devices':{'linodes':[i['id'] for i in inst]}})
print(r['id'])
