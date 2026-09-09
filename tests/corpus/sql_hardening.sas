/* SQL-hardening: two fixes.
   (1) BUG-sqlcalcgroupagg — `calculated <alias>` referencing an AGGREGATE alias
       under GROUP BY silently returned missing (substituteAggs can't reach a bare
       alias). Now the earlier SELECT items are bound so it resolves; chained
       calculated works too. SAS 9.4 SQL: CALCULATED references an already-computed
       column in the same query.
   (2) BUG-sqlsetopcols — a set operator (no CORRESPONDING) with mismatched column
       counts PANICKED (ragged rows hit an appendRow assert). SAS 9.4 matches by
       position and pads the shorter arm with missing values. */
data t; input g $ x; datalines;
A 10
A 20
B 5
;
run;
proc sql;
  select g, sum(x) as s, calculated s / 2 as half, calculated half + 1 as h1
  from t group by g;
quit;
data wide; input x n; datalines;
1 10
2 20
;
run;
data narrow; input y; datalines;
3
;
run;
proc sql;
  select x, n from wide union select y from narrow;
quit;
