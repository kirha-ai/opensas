data t; input id x; datalines;
1 10
2 20
;
run;
/* BUG-sqlupdatedropcol: a valid UPDATE/SELECT is unchanged, and DROP TABLE
   really removes the member (was a silent no-op) — after the drop,
   dictionary.tables lists only KEEPME. The loud error paths (unknown SET/SELECT
   column, DROP of an absent table/view) are covered by captured-diag tests in
   src/sql.zig. */
proc sql;
  update t set x = x + 1 where id = 2;
  select * from t;
  create table keepme as select id from t;
  drop table t;
  select memname from dictionary.tables where libname = "WORK" order by memname;
quit;
