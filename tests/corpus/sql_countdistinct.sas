/* PERF-sqlcountdistinct: COUNT(DISTINCT) now dedups via an O(1) hash set (same
   RowKeyCtx as SELECT DISTINCT), not a nested O(N^2) scan. This fixture proves the
   VALUES are unchanged (perf is verified separately). Ungrouped and grouped forms,
   with duplicates and a missing value that COUNT(DISTINCT) must exclude. */
data d;
  input c $ v;
  datalines;
a 1
a 1
a 2
b 3
b 3
b .
b 4
c 5
;
run;
proc sql;
  /* ungrouped: distinct v = {1,2,3,4,5} = 5; plain count(v) = 7 non-missing */
  select count(distinct v) as nd, count(v) as nv from d;
  /* grouped: a->{1,2}=2, b->{3,4}=2 (missing excluded), c->{5}=1 */
  select c, count(distinct v) as ndc from d group by c order by c;
quit;
