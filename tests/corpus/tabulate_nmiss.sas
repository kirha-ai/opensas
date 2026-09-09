/* BUG-tabnmiss: NMISS rendered "." in BOTH TABULATE paths — statValue(.nmiss)
   returns NaN ("filled by caller") but the renderer never supplied the count.
   It must show the cell's missing-observation count (cell obs - nonmissing n),
   exactly as PROC MEANS does. Cells below: a has 3 obs, 1 missing v (n=2,
   nmiss=1, sum=40); b has 3 obs, 2 missing v (n=1, nmiss=2, sum=50). 2-way:
   a*x=1, a*y=0, b*x=1, b*y=1 missing. */
data d;
  input g $ h $ v;
  datalines;
a x 10
a x .
a y 30
b x .
b y 50
b y .
;
run;
proc tabulate data=d;
  class g;
  var v;
  table g, v*(n nmiss sum);
run;
proc tabulate data=d;
  class g h;
  var v;
  table g, h*v*nmiss;
run;
