import sys,glob,os
from datetime import datetime
d,t0=sys.argv[1],int(sys.argv[2])
def nts(t):
    t=t.strip().replace('+00','')
    a,b=(t.split('.')+['0'])[:2]; return datetime.strptime(a+'.'+b.ljust(6,'0'),'%Y-%m-%d %H:%M:%S.%f').timestamp()
def acks(site):
    r=[]
    for f in glob.glob(f'{d}/{site}/c*.log'):
        c=os.path.basename(f)[:-4]
        for l in open(f):
            p=l.strip().split(' ',2)
            if len(p)>2 and p[1]=='ACK':
                i,ip,ts=p[2].split('|'); r.append((int(p[0]),c,int(i),ts))
    return sorted(r)
A,B=acks('a'),acks('b')
final={}
for l in open(f'{d}/final.txt'):
    q=l.strip().split('|')
    if len(q)==3: final[(int(q[0]),q[1])]=nts(q[2])
lastA=[a for a in A if a[0]>=t0]; firstB=[b for b in B if b[0]>=t0]
la=lastA[-1][0] if lastA else max(a[0] for a in A); fb=firstB[0][0] if firstB else None
print(f"site A: {len(A)} acked writes, last ack +{(la-t0)/1000:.1f}s after switchover start")
print(f"site B: {len(B)} acked writes, first ack +{(fb-t0)/1000:.1f}s" if fb else "site B: no writes acknowledged")
if fb: print(f"WRITE DOWNTIME across sites: {(fb-la)/1000:.1f}s (last ack on A -> first ack on B)")
lost=[a for a in A if not (final.get((a[2],a[1])) and abs(final[(a[2],a[1])]-nts(a[3]))<0.05)]
print(f"site-A acknowledged writes MISSING on new primary B: {len(lost)} of {len(A)}")
if lost: print(f"   lost writes acked between +{(lost[0][0]-t0)/1000:.1f}s and +{(lost[-1][0]-t0)/1000:.1f}s")
