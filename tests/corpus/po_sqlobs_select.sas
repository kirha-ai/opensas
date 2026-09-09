data d;
  input id val;
  datalines;
1 5
2 15
3 25
4 35
;
run;
proc sql;
  create table hi as select id, val from d where val > 12;
quit;
data _null_;
  n = &sqlobs;
  put "rows_selected=" n;
run;
proc sql;
  delete from d where val < 8;
quit;
data _null_;
  m = &sqlobs;
  put "rows_deleted=" m;
run;
