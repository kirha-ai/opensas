/* PROC MEANS with CLASS renders ONE combined table (class var as a column, a row
   per level) rather than separate per-level blocks (BUG-meansclass-layout) */
data d;
  input trt $ v;
  datalines;
A 10
A 20
A 30
B 40
B 60
;
run;
proc means data=d n mean std min max;
  class trt;
  var v;
run;
