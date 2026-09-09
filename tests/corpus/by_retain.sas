data have;
  input grp $ x;
  datalines;
A 10
A 20
A 30
B 5
B 15
;
run;

data _null_;
  set have;
  by grp;
  retain total;
  if first.grp then total = 0;
  total = total + x;
  if last.grp then put "grp=" grp " total=" total;
run;
