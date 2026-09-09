data have;
  input dept $ name $ age;
  datalines;
B Tom 40
A Sue 30
A Ann 25
B Al 22
;
run;

proc sort data=have;
  by dept age;
run;

data _null_;
  set have;
  put "dept=" dept " name=" name " age=" age;
run;
