/* BUG-sqlexistsalias: correlated EXISTS / NOT EXISTS must resolve the outer
   table ALIAS (e.col), not just the table name. */
data emp; input id dept; datalines;
1 10
2 20
3 10
;
run;
data dept; input dept; datalines;
10
;
run;
proc sql;
  select id from emp e where exists (select 1 from dept x where x.dept = e.dept);
  select id from emp e where not exists (select 1 from dept x where x.dept = e.dept);
quit;
