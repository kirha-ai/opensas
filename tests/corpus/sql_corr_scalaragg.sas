/* PERF-sqlcorrsubqsel-agg: an AGGREGATE correlated scalar subquery in the SELECT
   list must give identical results whether resolved by the hash fast path (bucket
   inner by key, fold once) or the per-row loop. Covers: distinct + duplicate inner
   keys, a no-match key (empty group → count 0, other folds missing), each safe
   fold, a char min/max, and a bailed shape (median → per-row) that must still be
   correct. */
data outer;
  do k = 1 to 5; output; end;   /* keys 1..5; 5 has no inner rows */
run;
data inner;
  input k v;
  datalines;
1 10
2 20
2 40
3 30
3 90
3 60
4 70
;
run;
data cinner;
  input k lbl $;
  datalines;
1 alpha
2 zulu
2 mike
3 bravo
;
run;

/* every safe fold + count(*) and a no-match key (5) */
proc sql; create table r1 as
  select k,
         (select count(*) from inner where inner.k = outer.k) as n_star,
         (select count(v) from inner where inner.k = outer.k) as n_v,
         (select sum(v)   from inner where inner.k = outer.k) as s_v,
         (select avg(v)   from inner where inner.k = outer.k) as a_v,
         (select min(v)   from inner where inner.k = outer.k) as mn_v,
         (select max(v)   from inner where inner.k = outer.k) as mx_v
  from outer;
quit;
proc print data=r1 noobs; run;

/* char min/max fast path */
proc sql; create table r2 as
  select k,
         (select min(lbl) from cinner where cinner.k = outer.k) as lo,
         (select max(lbl) from cinner where cinner.k = outer.k) as hi
  from outer;
quit;
proc print data=r2 noobs; run;

/* median is NOT whitelisted → BAILS to the per-row path (must still be correct) */
proc sql; create table r3 as
  select k, (select median(v) from inner where inner.k = outer.k) as med
  from outer;
quit;
proc print data=r3 noobs; run;
