/* MULTISET-impl: real multiple/conditional SET in one DATA step.
   (1) `set a; set b;` — one-to-one PARALLEL read, each SET with its own cursor.
   (2) `if _n_=1 then set summary;` — the classic lookup: read once, RETAIN across
   every obs of the driving dataset. SAS 9.4 semantics. Synthesized (no PHI). */
data a; input x; datalines;
1
2
3
;
run;
data b; input y; datalines;
10
20
30
;
run;
data summary; input tot; datalines;
99
;
run;

/* one-to-one parallel read: obs k pairs a[k] with b[k] */
data _null_;
  set a;
  set b;
  put "para x=" x "y=" y;
run;

/* lookup: tot read once on _n_=1, retained onto every obs */
data _null_;
  set a;
  if _n_=1 then set summary;
  put "look x=" x "tot=" tot;
run;
