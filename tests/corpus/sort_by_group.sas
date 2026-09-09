data have;
  input g $ v;
  datalines;
B 3
A 1
A 2
B 4
;
run;

proc sort data=have;
  by g;
run;

data _null_;
  set have;
  by g;
  if first.g then put "start g=" g;
  put "  v=" v;
  if last.g then put "end g=" g;
run;
