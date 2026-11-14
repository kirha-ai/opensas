from pathlib import Path
from read_probe import read
root=Path(__file__).parent
selected={'constants-grid':['kgrid0','kgrid1','kgrid2','kgrid3','kgrid4','kgrid5','kgrid6','kgrid7','kgrid8','kgrid9'],
'heldout-schema':['held0','held1','held2','held3','held4','held5','held6','aligned'],
'grid-boundaries':['flat0','flat1','flat2','flat4','zeroiqr','boundslist'],
'exact-reflection-window':['reflected0','reflected1','reflected2'],
'extra-controls':['extra_k0','extra_k1','extra_k2','extra_k3','extra_k4','extra_k5','flatmise']}
lines=['# case|C|value|density|scaled|type']
for file,names in selected.items():
 tables,_=read(root/(file+'.log'))
 for name in names:
  for row in tables[name]:
   scaled=next(row[k] for k in ['_PERCENT_','_PROPORTION_','_COUNT_'] if k in row)
   lines.append('|'.join([name]+[format(row[k],'.17g') for k in ['_C_','_VALUE_','_DENSITY_']]+[format(scaled,'.17g'),row['_TYPE_']]))
path=root.parents[2]/'src/stat/testdata/univ_kernel_grid_dev3.txt';path.write_text('\n'.join(lines)+'\n')
print('Oracle grid rows:',len(lines)-1)
