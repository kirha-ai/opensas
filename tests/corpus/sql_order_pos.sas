data d;
  input g $ v;
  datalines;
b 30
a 10
c 20
;
run;

proc sql;
  create table t as select g, v from d order by 2;
quit;

data _null_;
  set t;
  put "g=" g " v=" v;
run;
