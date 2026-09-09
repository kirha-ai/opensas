data a; input x @@; datalines;
5 1
;
run;
data b; input x @@; datalines;
3 9 2
;
run;
proc sql;
  create table u as select x from a union select x from b order by x;
quit;
data _null_;
  set u;
  put "u " x=;
run;
