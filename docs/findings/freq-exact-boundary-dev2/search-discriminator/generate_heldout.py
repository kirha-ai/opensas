from pathlib import Path
from discriminator import HELD
s=['ods exclude all;']
for i,(n1,n2,a) in enumerate(HELD):
 s.append(f'data t;input r c n;datalines;\n1 1 0\n1 2 {n1}\n2 1 {n2}\n2 2 0\n;\nrun;')
 for method in ['noscore','score']:
  s.append(f'ods output RelRisk1ExactCL=o{i}{method};proc freq data=t;weight n / zeros;tables r*c / relrisk alpha={float(a)};exact relrisk(method={method});run;')
  s.append(f'data _null_;set o{i}{method};if Name1="XU_RRC1" then put "HOLD,{n1},{n2},{float(a)},{method}," nValue1 best32.;run;')
Path(__file__).with_name('heldout.sas').write_text('\n'.join(s))
