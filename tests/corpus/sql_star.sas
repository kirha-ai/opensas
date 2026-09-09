data have;
  input a b;
  datalines;
1 2
3 4
;
run;

proc sql;
  create table c as select * from have;
quit;

data _null_;
  set c;
  put "a=" a " b=" b;
run;
