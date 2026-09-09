data master;
  input id v;
  datalines;
1 10
2 20
3 30
;
run;
data master;
  modify master;
  v = v + 100;
run;
data _null_;
  set master;
  put "row " id= v=;
run;
