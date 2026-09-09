/* BUG-sqlaggwherefilter: a summary function (sum/min/max/count/…) in a WHERE
   clause is illegal in SAS 9.4 ("Summary functions are not allowed in the WHERE
   clause." — aggregates belong in HAVING). It was silently dispatched as the
   per-row DATA-step function of the same name (max(v) -> v, so `v >= max(v)`
   kept EVERY row), dropping the filter entirely. It must now fail loud.
   Fail-loud paths are asserted via the captured-diagnostics test in sql.zig;
   here we prove the LEGITIMATE neighbours stay byte-identical: the same logic
   done correctly via HAVING or a subquery, and a plain per-row WHERE. */
data t;
  input v;
  datalines;
3
9
30
;
run;
proc sql;
  /* the same "keep the max row" logic, done correctly via HAVING */
  title 'having max';
  select v from t having v >= max(v);
quit;
proc sql;
  /* a subquery's own aggregate is fine — the outer WHERE stays per-row */
  title 'where subquery-agg';
  select v from t where v >= (select max(v) from t);
quit;
proc sql;
  /* a plain non-aggregate WHERE still filters per-row */
  title 'plain where';
  select v from t where v > 5;
quit;
