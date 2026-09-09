data d;
  input g $ v;
  datalines;
a 1e400
b 5
;
run;

proc tabulate data=d;
  class g;
  var v;
  table g, v*sum;
run;
