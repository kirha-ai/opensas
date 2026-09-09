/* PERF-sqlupdatecorr correctness fixture: a correlated scalar SET subquery
   `update m set v = (select nv from t where t.id = m.id)` reuses the
   SELECT-list single-equality hash path (was: the inner query re-executed per
   target row — O(N*M), 82s/4.4GB at N=20k). Pure optimization — values must be
   byte-identical to the per-row path: first-match-wins on duplicate inner
   keys, no-match -> missing, empty-group aggregate fold, alias + WHERE forms. */
data m;
  input id v w s;
  datalines;
1 0 0 0
2 0 0 0
3 0 0 0
. 0 0 0
;
run;
data t;
  input id nv;
  datalines;
1 70
2 71
2 72
. 77
;
run;

proc sql;
  /* plain correlated scalar: dup key 2 -> first match 71; id 3 -> missing. */
  update m set v = (select nv from t where t.id = m.id);
  /* aggregate sibling: per-key fold; no match -> empty fold (missing). */
  update m set s = (select max(nv) from t where t.id = m.id);
  /* alias + outer WHERE: only rows id > 1 are touched. */
  update m as x set w = (select nv from t where t.id = x.id) where id > 1;
quit;

data _null_;
  set m;
  put "id=" id " v=" v " w=" w " s=" s;
run;
