import json,os,sys,urllib.request
T=os.environ['LINODE_TOKEN']
def api(m,p,d=None):
    r=urllib.request.Request('https://api.linode.com/v4'+p,method=m,data=json.dumps(d).encode() if d is not None else None,headers={'Authorization':'Bearer '+T,'Content-Type':'application/json'})
    try: return json.load(urllib.request.urlopen(r))
    except urllib.error.HTTPError as e: print(e.read().decode(),file=sys.stderr); raise
