/* PERF-sqlremergeagg correctness fixture: a PROC SQL remerge's aggregates are a
   CONSTANT of their group, so they are computed once per group and broadcast
   (was: folded over the whole group for EVERY detail row — O(N·|grp|), i.e.
   quadratic for the no-GROUP-BY remerge where the group is the whole table).
   Pure optimization — rows, values and row order must be byte-identical to the
   old per-row path, so this pins exact stdout at fixed row positions.

   Every hoisted slot gets a probe here:
     - a bare SELECT-item aggregate            (sum(v))
     - an aggregate inside an expression       (v / sum(v) — percent of total)
     - an aggregate inside a CASE              (v > avg(v))
     - a GROUP BY remerge                      (sum(v) over g)
     - a HAVING with an aggregate in a remerge (having sum(v) > …)
     - the star remerge (select * … having)    (v > avg(v))
   The timing claim lives in the perf audit, not here: 1000 rows only. */

data big;
  do i = 1 to 1000;
    k = i;
    g = mod(i, 10);
    v = i * 1.5;
    output;
  end;
run;

/* no GROUP BY: the whole table is one group — the percent-of-total remerge. */
proc sql;
  create table o as
    select k, v,
           sum(v) as tot,
           v / sum(v) as pct,
           case when v > avg(v) then 'hi' else 'lo' end as band
    from big;
quit;
data _null_;
  set o;
  if _n_ <= 2 or _n_ >= 999 then
    put "o k=" k " v=" v " tot=" tot " pct=" pct " band=" band;
run;

/* GROUP BY remerge: per-group broadcast, and the HAVING carries its own
   aggregate (sum(v) > 75000 keeps some groups — 75750 — and drops others —
   74400 — so the filter is real in both directions). */
proc sql;
  create table p as
    select g, k, v, sum(v) as gtot
    from big
    group by g
    having sum(v) > 75000;
quit;
data _null_;
  set p;
  if k <= 20 or k >= 990 then
    put "p g=" g " k=" k " v=" v " gtot=" gtot;
run;

/* star remerge: `select * … having <agg>` — one output row per surviving input
   row, aggregate resolved over the row's group (no GROUP BY → whole table). */
proc sql;
  create table h as
    select * from big
    having v > avg(v);
quit;
data _null_;
  set h end=eof;
  n + 1;
  if _n_ <= 2 or eof then put "h k=" k " g=" g " v=" v;
  if eof then put "h rows=" n;
run;
