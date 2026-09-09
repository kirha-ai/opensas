/* BUG-transposesuffix: SUFFIX= was silently swallowed by the option loop —
   columns came out P1 P2 instead of P1_x P2_x, rc=0.
   GAP-transposelet: LET was likewise swallowed; a duplicate ID aborted rc=1
   instead of keeping the LAST value with no error, as SAS does. */
data d;
  input g v;
  datalines;
1 10
1 20
2 30
;
run;
proc transpose data=d out=o prefix=P suffix=_x;
  by g;
  var v;
run;
proc print data=o noobs; run;

/* LET + dup numeric ID (value 1 twice in the group): keep the LAST value
   (v=20), no error. PREFIX+SUFFIX here also pins the decorated-name dedup
   lookup — the fill loop must find C1_s for BOTH dup rows, not fall back to
   the positional index (which would write the second dup into C2_s). */
data d2;
  input g id v;
  datalines;
1 1 10
1 1 20
1 2 30
;
run;
proc transpose data=d2 out=o2 prefix=C suffix=_s let;
  by g;
  var v;
  id id;
run;
proc print data=o2 noobs; run;
