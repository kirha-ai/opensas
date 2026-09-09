data have;
  input dept $ sales;
  datalines;
A 10
A 20
B 30
;
run;

data _null_;
  set have;
  by dept;
  if first.dept then put "FIRST=" dept;
  put "dept=" dept " sales=" sales;
  if last.dept then put "LAST=" dept;
run;
