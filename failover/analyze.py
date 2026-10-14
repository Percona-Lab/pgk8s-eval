import sys
# usage: analyze.py probe.log start_ms [end_ms] -> list of outage intervals (last OK before -> first OK after)
f,st=sys.argv[1],int(sys.argv[2]); en=int(sys.argv[3]) if len(sys.argv)>3 else 10**15
rows=[]
for l in open(f):
    p=l.split(None,2)
    if len(p)<2 or not p[0].isdigit(): continue
    rows.append((int(p[0]),p[1],p[2].strip() if len(p)>2 else ''))
lastok=None; ip0=None; out=[]; cur=None
for t,s,x in rows:
    if t<st:
        if s=='OK': lastok=t; ip0=x
        continue
    if t>en: break
    if s=='FAIL':
        if cur is None: cur=[lastok or t,None,0,{}]
        cur[2]+=1; k=x[:70]; cur[3][k]=cur[3].get(k,0)+1
    else:
        if cur: cur[1]=t; out.append((cur,x)); cur=None
        lastok=t; ipn=x
if cur: out.append((cur,'NOT RECOVERED'))
if not out: print(f"no failed writes; primary {ip0}"); sys.exit()
tot=sum(((c[1] or en)-c[0]) for c,_ in out)/1000
print(f"main outage {((out[0][0][1] or en)-out[0][0][0])/1000:.1f}s starting +{(out[0][0][0]-st)/1000:.1f}s; {len(out)} interval(s), total {tot:.1f}s; primary {ip0} -> {out[-1][1]}")
for c,x in out:
    print(f"   +{(c[0]-st)/1000:.1f}s .. +{((c[1] or en)-st)/1000:.1f}s  ({((c[1] or en)-c[0])/1000:.1f}s, {c[2]} fails) top error: {max(c[3].items(),key=lambda z:z[1])[0]}")
# disruption window: merge intervals with <10s OK gap between them
m=[]
for c,x in out:
    s,e=c[0],(c[1] or en)
    if m and s-m[-1][1]<10000: m[-1][1]=e; m[-1][2]+=c[2]
    else: m.append([s,e,c[2]])
print("DISRUPT " + "; ".join(f"+{(a-st)/1000:.1f}s..+{(b-st)/1000:.1f}s = {(b-a)/1000:.1f}s ({n} fails)" for a,b,n in m))
