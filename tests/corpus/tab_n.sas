data d;
  input g $ v;
  datalines;
a 10
a 20
b 5
;
run;

proc tabulate data=d;
  class g;
  var v;
  table g, v*n;
run;
