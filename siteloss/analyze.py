import sys,glob,os
from datetime import datetime,timezone
d=sys.argv[1]
def nts(t):
    t=t.strip().replace('+00','');a,b=(t.split('.')+['0'])[:2]
    return datetime.strptime(a+'.'+b.ljust(6,'0'),'%Y-%m-%d %H:%M:%S.%f').replace(tzinfo=timezone.utc).timestamp()
ev={}
for l in open(f'{d}/events.log'):
    p=l.split()
    if len(p)>=2 and p[0].isdigit() and p[1].isupper() and p[1] not in ev: ev[p[1]]=int(p[0])
def acks(c):
    r=[]
    for l in open(f'{d}/{c}.log'):
        p=l.strip().split(' ',2)
        if len(p)>2 and p[1]=='ACK': i,ip,ts=p[2].split('|'); r.append((int(p[0]),c,int(i),ts))
    return r
T=ev['SITE_A_LOST']; s=lambda ms:f"{(ms-T)/1000:+.1f}s"
print(f"events (relative to site-A power-off): "+", ".join(f"{k} {s(v)}" for k,v in sorted(ev.items(),key=lambda x:x[1])))
for op,name,wk in (('c','CloudNativePG','CNPG_B_WRITABLE'),('p','Percona','PCT_B_WRITABLE')):
    final={}
    for l in open(f'{d}/final_{"cnpg" if op=="c" else "pct"}_B.txt'):
        q=l.strip().split('|')
        if len(q)==3: final[(int(q[0]),q[1])]=nts(q[2])
    A=sorted(acks(op+'A1')+acks(op+'A2')); B=sorted(acks(op+'B1'))
    pre=[a for a in A if a[0]<T]; post=[a for a in A if a[0]>=T]
    lost=[a for a in pre if not (final.get((a[2],a[1])) and abs(final[(a[2],a[1])]-nts(a[3]))<0.05)]
    fb=[b for b in B if b[0]>=ev['PROMOTE_B']]
    print(f"\n== {name}")
    print(f"  acked on A before loss: {len(pre)}; last A ack {s(pre[-1][0])}")
    print(f"  LOST (acked on A, missing on promoted B): {len(lost)}" + (f"  -> acked from {s(lost[0][0])} to {s(lost[-1][0])} (RPO ~{(T-lost[0][0])/1000:.1f}s of writes)" if lost else ""))
    print(f"  B writable (SQL check) {s(ev.get(wk,0))}  = {(ev.get(wk,0)-ev['PROMOTE_B'])/1000:.1f}s after promote command")
    if fb: print(f"  first write acked on B {s(fb[0][0])} = {(fb[0][0]-ev['PROMOTE_B'])/1000:.1f}s after promote; total write outage {(fb[0][0]-pre[-1][0])/1000:.1f}s (incl. {(ev['PROMOTE_B']-T)/1000:.0f}s decision delay)")
    else: print("  NO write acknowledged on B")
    z=[a for a in post if a[0]>=ev['BOOT_SITE_A']]
    if z:
        zr=[a for a in z if a[0]<ev.get('REJOIN_A',1e15)]
        print(f"  ZOMBIE writes accepted by returning site A: {len(z)} (first {s(z[0][0])}, {(z[0][0]-ev['SITE_A_K8S_API_UP'])/1000:+.1f}s vs A API up; last {s(z[-1][0])}, {(z[-1][0]-ev.get('REJOIN_A',0))/1000:+.1f}s vs rejoin cmd); in B final: {sum(1 for a in z if (a[2],a[1]) in final and abs(final[(a[2],a[1])]-nts(a[3]))<0.05)}")
    else: print("  zombie writes on returning site A: 0")
print(open(f'{d}/final_A.txt').read()); print('B counts:',open(f'{d}/final_B_counts.txt').read())
