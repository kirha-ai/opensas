/* PERF-sqlcorrsubq-ineq: a correlated scalar subquery whose inner WHERE is a
   COMPOUND equality and/or an INEQUALITY (`b.g=a.g and b.v>a.v`) buckets the
   inner table once on the composite equality key and binary-searches a sorted
   bucket per outer row — these pinned values must match the per-row fallback
   byte-for-byte. Covers: the rank-within-group idiom (count of b.v > a.v per
   group), all four inequality operators, MIN/MAX over the inequality (the
   next/previous-value idiom), count(col) with inner missings, compound-equality
   folds, an outer missing threshold, a no-match key, and a sum-over-inequality
   shape that deliberately stays on the fallback (sorted prefix sums would
   reorder f64 additions and could drift in the last ulp). */
data d;
  do id = 1 to 24;
    g = mod(id, 3);
    h = mod(id, 2);
    v = mod(id * 5, 7);
    if mod(id, 4) = 0 then v = .;   /* missings in the inequality column */
    w = id * 2;
    if mod(id, 5) = 0 then w = .;   /* missings in a counted column */
    output;
  end;
run;

/* rank-within-group + min/max over the inequality */
proc sql;
  create table r1 as
  select a.id, a.g, a.v,
         (select count(*) from d b where b.g = a.g and b.v >  a.v) as rnk,
         (select count(*) from d b where b.g = a.g and b.v >= a.v) as rnk_ge,
         (select count(*) from d b where b.g = a.g and b.v <  a.v) as below,
         (select min(b.v) from d b where b.g = a.g and b.v >  a.v) as nextv,
         (select max(b.v) from d b where b.g = a.g and b.v <= a.v) as prevv,
         (select count(b.w) from d b where b.g = a.g and b.v >  a.v) as nw
  from d a;
quit;
proc print data=r1 noobs; run;

/* compound equality (two keys) — count/sum/avg/min/max, flipped operand order */
proc sql;
  create table r2 as
  select a.id, a.g, a.h,
         (select count(*) from d b where b.g = a.g and b.h = a.h) as n2,
         (select sum(b.w) from d b where b.g = a.g and b.h = a.h) as sw,
         (select avg(b.v) from d b where a.g = b.g and a.h = b.h) as av,
         (select min(b.w) from d b where b.g = a.g and b.h = a.h) as mnw
  from d a;
quit;
proc print data=r2 noobs; run;

/* no-match key (g=9) and an outer missing threshold */
data o;
  id = 91; g = 9; v = 3; output;
  id = 92; g = 1; v = .; output;
run;
proc sql;
  create table r3 as
  select a.id, a.g, a.v,
         (select count(*) from d b where b.g = a.g and b.v > a.v) as rnk,
         (select min(b.v) from d b where b.g = a.g and b.v > a.v) as nextv
  from o a;
quit;
proc print data=r3 noobs; run;

/* sum/avg over an inequality BAILS to the per-row path — pin that it stays correct */
proc sql;
  create table r4 as
  select a.id,
         (select sum(b.v) from d b where b.g = a.g and b.v > a.v) as sgt,
         (select avg(b.w) from d b where b.g = a.g and b.v < a.v) as alt
  from d a;
quit;
proc print data=r4 noobs; run;
