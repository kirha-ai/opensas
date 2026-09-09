/* PERF-sqlcorrsubqsel: a correlated scalar subquery in the SELECT list must give
   identical results whether resolved by the hash fast path or the per-row loop.
   Covers: distinct + duplicate inner keys (first match wins), no-match → missing,
   a char-valued select, and a scalar-in-expression that must BAIL to per-row. */
data t_out;
  do i = 1 to 6; k = i; output; end;
run;
/* duplicate key 2 (v=20 then v=99): first match must win */
data t_in;
  k = 2; v = 20; output; k = 2; v = 99; output;
  k = 4; v = 40; output; k = 6; v = 60; output;
run;
data t_lbl;
  k = 2; lbl = "TWO"; output; k = 4; lbl = "FOUR"; output;
run;

/* plain scalar subquery → fast path (v: 2->20, 4->40, 6->60, else missing) */
proc sql; create table r1 as
  select k, (select v from t_in where t_in.k = t_out.k) as vv
  from t_out;
quit;
proc print data=r1 noobs; run;

/* char-valued scalar subquery → fast path */
proc sql; create table r2 as
  select k, (select lbl from t_lbl where t_lbl.k = t_out.k) as name
  from t_out;
quit;
proc print data=r2 noobs; run;

/* scalar subquery wrapped in an expression → BAILS to the per-row path */
proc sql; create table r3 as
  select k, (select v from t_in where t_in.k = t_out.k) + 1000 as vplus
  from t_out;
quit;
proc print data=r3 noobs; run;
