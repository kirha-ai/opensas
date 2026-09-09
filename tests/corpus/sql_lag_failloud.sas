/* BUG-lagdifsql: LAG/DIF/LAGn/DIFn are DATA-step functions with
   observation-order queue semantics; PROC SQL has no observation order, so
   SAS 9.4 errors (function-cannot-be-located class). opensas used to evaluate
   them in SQL and invent data. The DATA-step LAG/DIF below proves the queue
   still works there; the `select lag(x)` query then fails LOUD — ERROR to the
   log, exit 1, no invented listing on stdout (per BUG-errhalt later steps are
   skipped after a step ERROR, real SAS batch behavior). The ERROR says "is
   invalid here" — rc-1 user-error wording (real SAS rejects LAG in SQL too),
   never the rc-2 "not supported" a downstream agent routes on
   (NOTE-typoarmgapwording, D-009). If the guard
   regresses, a bogus 3-row listing appears here and mismatches.
   expect-rc: 1 */
data t;
  input x;
  datalines;
10
14
19
;
run;
data _null_;
  set t;
  l = lag(x);
  d = dif(x);
  put "x=" x " lag=" l " dif=" d;
run;
proc sql;
  select lag(x) as lx from t;
quit;
