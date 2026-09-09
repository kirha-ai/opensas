data d;
  input a b c;
  datalines;
. . 7
. 5 9
1 2 3
;
run;

proc sql;
  create table t as select coalesce(a, b, c) as v from d;
quit;

data _null_;
  set t;
  put "v=" v;
run;
