/* PROC MEANS OUTPUT OUT= with 2 CLASS vars emits all 2^k _TYPE_ levels:
   0=overall, 1=by the 2nd var, 2=by the 1st var, 3=full cross (BUG-meansouttype-multiclass) */
data d;
  input arm $ sex $ v;
  datalines;
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
  output out=s n=cnt mean=avg;
run;
proc print data=s; run;
