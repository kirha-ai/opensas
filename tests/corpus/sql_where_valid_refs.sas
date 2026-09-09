/* Regression guard for BUG-sqlwhereunknown / BUG-sqlwherecalcagg (9d228aa):
   the new WHERE column-ref validation must NOT wrongly reject VALID refs.
   Every WHERE below is legal and must still filter (over-strict validation
   here = HIGH regression, silent data loss). Covers: plain column, qualified
   <table>.col, function call, CALCULATED non-aggregate alias, IN-subquery. */
data d;
  input k $ v;
  datalines;
a 1
a 2
b 5
;
run;
proc sql;
  create table t2 as select k, v      from d where v > 1;
  create table t3 as select k         from d where d.v > 1;
  create table t4 as select k         from d where upcase(k) = 'A';
  create table t5 as select v, v*2 as vv from d where calculated vv > 2;
  create table t7 as select k         from d where v in (select v from d where v > 1);
quit;
proc print data=t2 noobs; run;
proc print data=t3 noobs; run;
proc print data=t4 noobs; run;
proc print data=t5 noobs; run;
proc print data=t7 noobs; run;
