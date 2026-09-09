data d;
  input x;
  datalines;
1
2
3
;
run;

proc sql;
  create table c as select count(*) as n from d;
quit;

data _null_;
  set c;
  put "n=" n;
run;
