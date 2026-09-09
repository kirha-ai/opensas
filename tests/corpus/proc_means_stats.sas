data d;
  input x;
  datalines;
10
20
30
40
50
;
run;

proc means data=d mean sum median min max;
  var x;
run;
