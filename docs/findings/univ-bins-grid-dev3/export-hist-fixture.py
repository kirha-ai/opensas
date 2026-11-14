from pathlib import Path
from read_probe import read
root=Path(__file__).parent
sets={'shared-counts':['shared'+str(i) for i in [0,1,2,3,4,6,7]]+['count'+str(i) for i in range(12)],
'constant-shared-grid':['const'+str(i)+'_'+mode for i in range(7) for mode in ['mid','end','uniform']],
'window-controls':['limit'+str(i) for i in range(10)],
'window-order':['reverse'+str(i) for i in range(4)],
'exact-reflection-window':['mixed'+str(i) for i in range(4)],
'extra-controls':['tie'+str(i) for i in range(3)]}
lines=['# case|group|location|percent|count']
for file,names in sets.items():
 tables,_=read(root/(file+'.log'))
 for name in names:
  for row in tables[name]:
   loc=next(row[k] for k in ['_MIDPT_','_MINPT_','_MAXPT_'] if k in row)
   lines.append('|'.join([name,row.get('g','')]+[format(v,'.17g') for v in [loc,row['_OBSPCT_'],row['_COUNT_']]]))
(root.parents[2]/'src/stat/testdata/univ_histogram_bins_dev3.txt').write_text('\n'.join(lines)+'\n')
print('Oracle histogram rows',len(lines)-1)
