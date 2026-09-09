data have;
  input x;
  datalines;
10
20
30
;
run;

proc transpose data=have out=want prefix=c;
  var x;
run;

data _null_;
  set want;
  put "c1=" c1 " c2=" c2 " c3=" c3;
run;
