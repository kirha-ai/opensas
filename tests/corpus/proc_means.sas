data have;
  input x;
  datalines;
10
20
30
40
;
run;

proc means data=have;
run;
