data d;
  input x y;
  datalines;
30 1
10 3
20 2
;
run;

/* ORDER BY a column NOT in the SELECT list: SAS sorts by it anyway
   (with a NOTE) — x comes out ordered by y, not in input order. */
proc sql;
  create table t as select x from d order by y;
quit;

data _null_;
  set t;
  put "nonselected=" x;
run;

proc sql;
  create table t2 as select x from d order by y desc;
quit;

data _null_;
  set t2;
  put "desc=" x;
run;

/* control: ORDER BY a selected column is unchanged */
proc sql;
  create table t3 as select x from d order by x;
quit;

data _null_;
  set t3;
  put "control=" x;
run;
