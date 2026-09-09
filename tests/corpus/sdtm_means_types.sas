/* Two-way subtotals via _TYPE_ in MEANS OUTPUT (all class subsets) */
data d; input arm $ sex $ v; datalines;
DRUG M 10
DRUG F 20
DRUG M 30
PLAC M 40
PLAC F 50
;
run;
proc means data=d noprint;
  class arm sex;
  var v;
  output out=s n=cnt sum=tot;
run;
proc print data=s; run;
