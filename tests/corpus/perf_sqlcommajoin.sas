/* PERF-sqlcommajoin correctness fixture: a comma-join whose equijoin predicates
   sit in WHERE must hash-join via the pushed col=col conjuncts (was: the full
   cartesian product materialized before the WHERE filter — O(N^2)/O(N^3)
   time+RAM). Pure optimization — rows + order must be byte-identical to the
   old nested-loop path. Covers: duplicate keys both sides (bucket order),
   keys present on one side only (dropped), a residual non-equality WHERE term
   (partial push), a 3-way chain, char keys, and missing=missing matches.
   (A blowup-sized perf probe would be too slow/OOM for the corpus.) */
data a;
  input id av;
  datalines;
1 10
2 20
2 21
3 30
9 90
. 99
;
run;
data b;
  input id bv;
  datalines;
1 100
2 200
2 201
4 400
. 999
;
run;
data c;
  input id cv;
  datalines;
1 1000
2 2000
3 3000
;
run;

/* 2-way, no ORDER BY: pins the nested-loop row order (a-scan x b-scan). */
proc sql;
  create table j2 as select a.id, av, bv from a, b where a.id = b.id;
quit;
data _null_;
  set j2;
  put "j2 id=" id " av=" av " bv=" bv;
run;

/* residual non-equality term: only the equijoin conjunct is pushed. */
proc sql;
  create table j2r as select a.id, av, bv from a, b where a.id = b.id and bv > 150;
quit;
data _null_;
  set j2r;
  put "j2r id=" id " av=" av " bv=" bv;
run;

/* 3-way chain: each comma step gets its own linking conjunct pushed. */
proc sql;
  create table j3 as select a.id, av, bv, cv from a, b, c where a.id = b.id and b.id = c.id;
quit;
data _null_;
  set j3;
  put "j3 id=" id " av=" av " bv=" bv " cv=" cv;
run;

/* char keys (trailing-blank-insensitive) hash the same as the loop's compare. */
data x;
  length k $3;
  input k $ xv;
  datalines;
a 1
b 2
c 3
;
run;
data y;
  length k $3;
  input k $ yv;
  datalines;
a 10
b 20
b 21
d 40
;
run;
proc sql;
  create table j4 as select x.k, xv, yv from x, y where x.k = y.k;
quit;
data _null_;
  set j4;
  put "j4 k=" k " xv=" xv " yv=" yv;
run;
