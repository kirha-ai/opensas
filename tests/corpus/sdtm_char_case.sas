/* Upcase / lowcase / propcase a mixed-case string */
data d; input raw $20.; datalines;
mIxEd CaSe TeXt
;
run;
data c;
  set d;
  length u $20 l $20 p $20;
  u = upcase(raw);
  l = lowcase(raw);
  p = propcase(raw);
run;
proc print data=c; var u l p; run;
