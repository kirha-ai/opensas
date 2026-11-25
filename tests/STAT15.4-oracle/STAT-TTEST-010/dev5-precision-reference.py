"""Independent 70-digit UMPU verification; requires mpmath. No OpenSAS math is called.
S154 physical pp.10621-10622; extracts reference Statistics column names from
all vertical header panels and independently solves mass/moment equations.
"""
from pathlib import Path
import csv,json,re,sys
import mpmath as mp
mp.mp.dps=70
root=Path(__file__).resolve().parent/'dev5-evidence'
reference=(Path(__file__).resolve().parent/'ods_tables.expected.txt').read_text().splitlines()
indices=[i for i,line in enumerate(reference) if re.match(r'^\s*x\s+',line)]
assert len(indices)==10
num=re.compile(r'^(?:_|\.|[-+]?\d+(?:\.\d*)?(?:[Ee][-+]?\d+)?)$')
def numeric_lines(start,end):
 return [(i,reference[i].split()) for i in range(start,end) if reference[i].split() and all(num.fullmatch(x) for x in reference[i].split())]
def vertical(start,end):
 lines=[line for line in reference[start:end] if line.strip()]
 assert all(all(len(x)==1 for x in line.split()) for line in lines)
 return [''.join(line[j] for line in lines if j<len(line) and not line[j].isspace()) for j in range(max(map(len,lines)))]
def compact(names):return [x for x in names if x]
start=next(i for i,line in enumerate(reference) if line.strip().startswith('Folded F'))+1
extra=numeric_lines(indices[3]+1,indices[4]);assert len(extra)==8
names=compact(vertical(start,indices[0]))+compact(vertical(indices[3]+1,extra[0][0]))+compact(vertical(extra[3][0]+1,extra[4][0]))
actual=list(csv.DictReader((root/'stats.csv').open()))
assert list(actual[0])==names,(list(actual[0]),names)
rows=[]
for j,index in enumerate(indices[:4]):
 vals=reference[index].split()[-4:]+extra[j][1]+extra[j+4][1]
 assert len(vals)==12
 rows.append(dict(zip(names[3:],vals)))
# Independently solve the two chi-square acceptance equations. No OpenSAS
# probability routines or reference endpoints are used as solver inputs.
def cdf(x,df):return mp.gammainc(df/2,0,x/2,regularized=True)
def umpu(sd,df):
 c1,c2=mp.findroot(lambda a,b:(cdf(b,df)-cdf(a,df)-mp.mpf('.95'),df*mp.log(a/b)-a+b),(mp.mpf(df)/4,mp.mpf(df)*3),tol=mp.mpf('1e-60'),maxsteps=100)
 return sd*mp.sqrt(df/c2),sd*mp.sqrt(df/c1)
data=[[43,90,84,87,116,95],[86,99,93,92,121,71]]
means=[sum(map(mp.mpf,x))/len(x) for x in data]
variances=[sum((mp.mpf(v)-mu)**2 for v in x)/(len(x)-1) for x,mu in zip(data,means)]
sds=[mp.sqrt(v) for v in variances]+[mp.sqrt(sum(variances)/2)]
dfs=[mp.mpf(5),mp.mpf(5),mp.mpf(10)]
report=[]
for i,(sd,df) in enumerate(zip(sds,dfs)):
 low,high=umpu(sd,df)
 reflo=mp.mpf(rows[i]['UMPULowerCLStdDev']);refhi=mp.mpf(rows[i]['UMPUUpperCLStdDev'])
 actual_lo=mp.mpf(actual[i]['UMPULowerCLStdDev']);actual_hi=mp.mpf(actual[i]['UMPUUpperCLStdDev'])
 c1_ref=df*(sd/refhi)**2;c2_ref=df*(sd/reflo)**2
 item={'row':i+1,'df':str(df),'independent_lower':mp.nstr(low,55),'independent_upper':mp.nstr(high,55),'SAS_lower':str(reflo),'SAS_upper':str(refhi),'OpenSAS_lower':str(actual_lo),'OpenSAS_upper':str(actual_hi),'SAS_upper_abs_error':mp.nstr(abs(refhi-high),25),'OpenSAS_upper_abs_error':mp.nstr(abs(actual_hi-high),25),'SAS_mass_residual':mp.nstr(cdf(c2_ref,df)-cdf(c1_ref,df)-mp.mpf('.95'),25),'SAS_moment_residual':mp.nstr(cdf(c2_ref,df+2)-cdf(c1_ref,df+2)-mp.mpf('.95'),25)}
 assert abs(actual_lo-low)<mp.mpf('2e-12') and abs(actual_hi-high)<mp.mpf('2e-12')
 report.append(item)
print(json.dumps({'all_statistics_column_names_match':True,'reference_schema':names,'umpu':report},indent=2))
