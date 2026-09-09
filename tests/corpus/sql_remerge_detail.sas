/* BUG-sqlremergedetail: a no-GROUP-BY select mixing a detail column with an
   aggregate REMERGES in SAS 9.4 — the aggregate is computed over the whole
   table and broadcast across every detail row, so N rows come back, not the
   single collapsed group row. `tot` = 100 on every row; `frac` = x/100 per row.
   Guards: a pure-aggregate select (no detail column) still returns 1 row, and
   an explicit GROUP BY query is unaffected. */
data a; input id x; datalines;
1 10
2 20
3 30
4 40
;
run;
proc sql; select id, x, sum(x) as tot, x/sum(x) as frac from a; quit;
proc sql; select sum(x) as tot from a; quit;
proc sql; select id, sum(x) as tot from a group by id; quit;
