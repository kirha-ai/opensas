/* GAP-sqlderivedtable: a derived table (SAS 9.4 SQL "in-line view") is a subquery
   used as a standalone FROM source, with an optional alias. It is materialized to a
   temp result and treated as a table; alias-qualified columns (t.n) resolve against
   it and an outer WHERE/JOIN can reference its columns. Two prior bugs: the alias was
   reused as the temp table name (table==alias → no rows), and `alias.col` never
   matched an unqualified derived column (BUG-sqlqualcol, which also broke `t.col` on a
   plain `from x as t`). */
data x; input g $ v; datalines;
A 1
A 2
B 3
;
run;
data lk; input g $ lab $; datalines;
A alpha
B bravo
;
run;
proc sql;
  /* derived table with GROUP BY + alias-qualified outer WHERE */
  select t.g, t.n from (select g, count(*) as n from x group by g) as t where t.n > 1;
quit;
proc sql;
  /* derived table joined to a real table */
  select d.g, d.n, lk.lab
  from (select g, count(*) as n from x group by g) as d
  inner join lk on d.g = lk.g
  order by d.g;
quit;
