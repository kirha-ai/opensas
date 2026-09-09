/* BUG-sqlaggqualcol: a table-qualified column inside an aggregate (max(y.v),
   sum(y.v)) used to panic (null-deref) because the qualifier wasn't stripped
   before the column lookup. Plain and correlated-subquery forms both. */
data d;
  input id v;
  datalines;
1 5
2 8
3 7
;
run;
proc sql;
  select max(y.v) as mx, sum(y.v) as sm from d y;
quit;
proc sql;
  select id, (select sum(y.v) from d y where y.id <= d.id) as running from d;
quit;
