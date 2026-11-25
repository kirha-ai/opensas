"""Validate actual SVG data AND painted coordinates, using original input/listing.
Run from any directory with Python3; uses only the standard library.
Blom convention: https://support.sas.com/documentation/cdl/en/sgug/59902/HTML/default/dist_sect21.htm
"""
from pathlib import Path
from fractions import Fraction
from statistics import NormalDist,mean,stdev
import xml.etree.ElementTree as ET
import re,json,math
folder=Path(__file__).resolve().parent
source=(folder/'graph_names.sas').read_text()
reference=(folder/'graph_names.expected.txt').read_text()
rows=re.search(r'\bdatalines\s*;(.+?);\s*run;',source,re.I|re.S)[1]
groups={}
for line in rows.splitlines():
 fields=line.split()
 if fields:groups.setdefault(fields[2],[]).append(float(fields[0]))
labels=sorted(groups)
expected_intervals={}
for line in reference.splitlines():
 fields=line.split()
 if fields[:2]!=['Diff','(1-2)']:continue
 if fields[2]=='Pooled' and len(fields)==9 or fields[2]=='Satterthwaite' and len(fields)==6:
  expected_intervals[fields[2]]=list(map(float,fields[3:6]))
assert set(expected_intervals)=={'Pooled','Satterthwaite'}
ns={'s':'http://www.w3.org/2000/svg'}
def axis(group):
 path=group.find("s:path[@class='axis']",ns)
 return list(map(float,re.fullmatch(r'M([\d.]+) ([\d.]+)V([\d.]+)H([\d.]+)',path.attrib['d']).groups()))
interval=ET.parse(folder/'dev5-evidence/interval.svg').getroot()
l,t,b,r=axis(interval)
ticks=[float(e.text) for e in interval.findall('s:text',ns) if b<float(e.attrib.get('y',0))<b+30]
xmin,xmax=min(ticks),max(ticks)
items=interval.findall("s:g[@class='interval-row']",ns);assert len(items)==2
exact_difference=float(sum(map(Fraction,groups[labels[0]]))/len(groups[labels[0]])-sum(map(Fraction,groups[labels[1]]))/len(groups[labels[1]]))
interval_checks=[]
for item in items:
 method=item.attrib['data-method'];values=[float(item.attrib['data-'+name]) for name in ['estimate','lower','upper']]
 assert abs(values[0]-exact_difference)<2e-14
 assert all(abs(actual-want)<=.00005 for actual,want in zip(values,expected_intervals[method]))
 cx=float(item.find('s:circle',ns).attrib['cx']);line=item.find("s:path[@class='interval']",ns).attrib['d']
 lo,y,hi=map(float,re.fullmatch(r'M([\d.]+) ([\d.]+)H([\d.]+)',line).groups())
 pixel=lambda x:l+(r-l)*(x-xmin)/(xmax-xmin)
 assert abs(cx-pixel(values[0]))<=.006 and abs(lo-pixel(values[1]))<=.006 and abs(hi-pixel(values[2]))<=.006
 assert t<y<b and l<=lo<=cx<=hi<=r
 interval_checks.append({'method':method,'estimate':values[0],'lower':values[1],'upper':values[2],'painted_coordinates_match':True})
visible=' '.join(' '.join(interval.itertext()).split())
assert 'group: A - B | x' in visible and 'Difference in means' in visible
assert '95% confidence intervals' in visible
qq=ET.parse(folder/'dev5-evidence/qq.svg').getroot()
panels=qq.findall("s:g[@class='qq-panel']",ns);assert len(panels)==2
qq_checks=[]
for panel,label in zip(panels,labels):
 assert panel.attrib['data-group']==label
 observations=sorted(groups[label]);n=len(observations)
 assert int(panel.attrib['data-n'])==n
 assert abs(float(panel.attrib['data-mean'])-mean(observations))<2e-13
 assert abs(float(panel.attrib['data-sd'])-stdev(observations))<1e-12
 l,t,b,r=axis(panel)
 xmin,xmax,ymin,ymax=(float(panel.attrib['data-'+name]) for name in ['xmin','xmax','ymin','ymax'])
 points=panel.findall('s:circle',ns);assert len(points)==n
 for i,(point,observed) in enumerate(zip(points,observations),1):
  probability=float(Fraction(8*i-3,8*n+2));quantile=NormalDist().inv_cdf(probability)
  assert float(point.attrib['data-observed'])==observed
  assert abs(float(point.attrib['data-probability'])-probability)<=2e-16
  assert abs(float(point.attrib['data-quantile'])-quantile)<2e-9
  cx=float(point.attrib['cx']);cy=float(point.attrib['cy'])
  assert abs(cx-(l+(r-l)*(quantile-xmin)/(xmax-xmin)))<=.006
  assert abs(cy-(b-(b-t)*(observed-ymin)/(ymax-ymin)))<=.006
  assert l<=cx<=r and t<=cy<=b
 line=panel.find("s:path[@class='reference']",ns)
 assert abs(float(line.attrib['data-intercept'])-mean(observations))<2e-13
 assert abs(float(line.attrib['data-slope'])-stdev(observations))<1e-12
 qq_checks.append({'group':label,'n':n,'all_observed_and_quantile_values_verified':True,'painted_coordinates_match':True})
visible=' '.join(' '.join(qq.itertext()).split())
for label in labels:assert f'group = {label} (n=6)' in visible
assert visible.count('Normal Quantile')==2 and 'Circles: observations' in visible
print(json.dumps({'intervals':interval_checks,'qq_panels':qq_checks,'total_qq_points':sum(x['n'] for x in qq_checks),'labels_axes_legends_verified':True,'tolerances':{'listing_interval_endpoints':.00005,'normal_quantiles':2e-9,'svg_pixel_coordinates':.006}},indent=2))
