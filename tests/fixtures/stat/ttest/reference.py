"""Independent TTEST-010 numeric contract (not an OpenSAS output generator).

SAS/STAT 15.4 physical pp.10621-10626: normal summaries, Student mean
intervals, chi-square standard-deviation intervals, pooled/Welch tests and
folded-F equality. UMPU uses BOTH mass and first-moment equations, p.10622.
Run with mpmath >= 1.3. Values below are consumed as literals by Zig tests;
this derivation does not run during the gate and reads no oracle files.
"""
import mpmath as m
m.mp.dps = 70
alpha = m.mpf('0.05')

def inverse(cdf, p):
    lo, hi = m.mpf(0), m.mpf(1)
    while cdf(hi) < p:
        hi *= 2
    for _ in range(250):
        mid = (lo + hi) / 2
        if cdf(mid) < p: lo = mid
        else: hi = mid
    return (lo + hi) / 2

def chi(x, df):
    return m.gammainc(df/2, 0, x/2, regularized=True)

def ttail(t, df):
    return m.betainc(df/2, m.mpf('0.5'), 0, df/(df+t*t), regularized=True)/2

def mean_bounds(mean, se, df):
    critical = inverse(lambda t: 1-ttail(t,df), 1-alpha/2)
    return mean-critical*se, mean+critical*se

def sd_bounds(sd, df):
    eq = [sd*m.sqrt(df/inverse(lambda x: chi(x,df), p)) for p in (1-alpha/2,alpha/2)]
    # Independent two-dimensional solve, unlike implementation's tail bisection.
    c1,c2=m.findroot(lambda lo,hi: (chi(hi,df)-chi(lo,df)-(1-alpha),
                                    chi(hi,df+2)-chi(lo,df+2)-(1-alpha)),
                     (df*(sd/eq[1])**2, df*(sd/eq[0])**2))
    return eq+[sd*m.sqrt(df/c2),sd*m.sqrt(df/c1)]

def sample(values):
    n=m.mpf(len(values)); mean=sum(map(m.mpf,values))/n
    sd=m.sqrt(sum((x-mean)**2 for x in values)/(n-1)); se=sd/m.sqrt(n)
    return [n,mean,*mean_bounds(mean,se,n-1),sd,*sd_bounds(sd,n-1),se,m.mpf(min(values)),m.mpf(max(values))]

a=sample([43,90,84,87,116,95]);b=sample([86,99,93,92,121,71])
diff=a[1]-b[1]; df=m.mpf(10); pooled=m.sqrt((a[4]**2+b[4]**2)/2)
se=m.sqrt(a[4]**2/6+b[4]**2/6)
welch=(a[4]**2/6+b[4]**2/6)**2/((a[4]**2/6)**2/5+(b[4]**2/6)**2/5)
p=[None,diff,*mean_bounds(diff,se,df),pooled,*sd_bounds(pooled,df),se,None,None]
w=[None,diff,*mean_bounds(diff,se,welch),None,None,None,None,None,se,None,None]
for row in (a,b,p,w):
    print('.{ '+', '.join('missing' if x is None else m.nstr(x,30) for x in row)+' },')
print('tests:')
for df in (m.mpf(10),welch):print(m.nstr(diff/se,30),m.nstr(df,30),m.nstr(2*ttail(diff/se,df),30))
f=a[4]**2/b[4]**2
print('Equality:', m.nstr(f,30),m.nstr(2*m.betainc(m.mpf('2.5'),m.mpf('2.5'),0,1/(1+f),regularized=True),30))
