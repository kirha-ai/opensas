/* PERF-sqlcorrsubq: correlated IN / EXISTS / NOT forms must produce identical
   results whether resolved by the hash semi-join fast path or the per-row loop.
   Covers: all-distinct + duplicate inner keys, NOT forms, and an empty-inner case. */
data t1;
  do i = 1 to 6; k = i; v = i * 10; output; end;
run;
/* t2 has duplicate keys (2,2,4,6,6): membership must ignore multiplicity */
data t2;
  k = 2; output; k = 2; output; k = 4; output; k = 6; output; k = 6; output;
run;
/* t3 shares no key with t1 — the empty-match case */
data t3;
  k = 100; output; k = 200; output;
run;

/* correlated IN  → 2,4,6 */
proc sql; create table r_in as
  select * from t1 where k in (select k from t2 where t2.k = t1.k); quit;
proc print data=r_in noobs; run;

/* correlated EXISTS → 2,4,6 */
proc sql; create table r_ex as
  select * from t1 where exists (select * from t2 where t2.k = t1.k); quit;
proc print data=r_ex noobs; run;

/* NOT IN → 1,3,5 */
proc sql; create table r_ni as
  select * from t1 where k not in (select k from t2 where t2.k = t1.k); quit;
proc print data=r_ni noobs; run;

/* NOT EXISTS → 1,3,5 */
proc sql; create table r_ne as
  select * from t1 where not exists (select * from t2 where t2.k = t1.k); quit;
proc print data=r_ne noobs; run;

/* EXISTS with empty match → no rows */
proc sql; create table r_empty as
  select * from t1 where exists (select * from t3 where t3.k = t1.k); quit;
proc print data=r_empty noobs; run;

/* NOT EXISTS with empty match → all rows 1..6 */
proc sql; create table r_all as
  select * from t1 where not exists (select * from t3 where t3.k = t1.k); quit;
proc print data=r_all noobs; run;
