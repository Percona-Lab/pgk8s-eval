import sys,glob,os,re
def nts(t):
    t=t.strip().replace('+00','')
    if '.' in t: a,b=t.split('.'); return a+'.'+b.ljust(6,'0')
    return t+'.000000'
# analyze_sb.py DIR T_PARTITION_MS [probe.log]
d,tp=sys.argv[1],int(sys.argv[2]); probe=sys.argv[3] if len(sys.argv)>3 else None
acks=[]; errs=0; rec=0
for f in sorted(glob.glob(d+'/c*.log')):
    c=os.path.basename(f)[:-4]
    for l in open(f):
        p=l.strip().split(' ',2)
        if len(p)<2: continue
        if p[1]=='ACK':
            i,ip,ts=p[2].split('|'); acks.append((int(p[0]),c,int(i),ip,ts.strip()))
        elif p[1]=='RECONNECT': rec+=1
        else: errs+=1
final={}
for l in open(d+'/final.txt'):
    q=l.strip().split('|')
    if len(q)==3: final[(int(q[0]),q[1])]=nts(q[2])
acks.sort()
pre=[a for a in acks if a[0]<tp]; old=pre[-1][3]
post=[a for a in acks if a[0]>=tp]
oldpost=[a for a in post if a[3]==old]; newc=[a for a in post if a[3]!=old]
print(f"old primary {old}; acks before partition {len(pre)}, after {len(post)} (by old primary {len(oldpost)}, by new primary {len(newc)}); client reconnects {rec}; client errors {errs}")
if oldpost: print(f"OLD primary acknowledged writes until +{(oldpost[-1][0]-tp)/1000:.1f}s after the partition")
if newc: print(f"writers' first ack from new primary at +{(newc[0][0]-tp)/1000:.1f}s")
tn=None
if probe:
    for l in open(probe):
        p=l.split()
        if len(p)>=3 and p[0].isdigit() and int(p[0])>=tp and p[1]=='OK' and p[2]!=old: tn=int(p[0]); break
    if tn: print(f"NEW primary accepting writes (new-connection probe via -rw) from +{(tn-tp)/1000:.1f}s")
if tn and oldpost and oldpost[-1][0]>tn:
    both=[a for a in oldpost if a[0]>=tn]
    print(f"DUAL-PRIMARY window: {(oldpost[-1][0]-tn)/1000:.1f}s, during which the old primary acknowledged {len(both)} writes")
from datetime import datetime
P=lambda t:datetime.strptime(t,'%Y-%m-%d %H:%M:%S.%f').timestamp()
def ok(a):
    f=final.get((a[2],a[1]))
    return f is not None and abs(P(f)-P(nts(a[4])))<0.05
lost=[a for a in acks if not ok(a)]
print(f"acknowledged writes LOST: {len(lost)} of {len(acks)} acknowledged ({len([a for a in lost if a[3]==old and a[0]>=tp])} acked by the isolated old primary after the partition)")
if lost: print(f"   lost writes were acknowledged between +{(lost[0][0]-tp)/1000:.1f}s and +{(lost[-1][0]-tp)/1000:.1f}s")
