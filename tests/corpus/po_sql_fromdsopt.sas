/* GH#33: a PROC SQL FROM/JOIN table-ref applies dataset options */
data one; a=1; output; a=2; output; run;
data two; a=1; b=9; output; a=2; b=8; output; run;
proc sql;
  /* where= on the FROM table filters rows (was: "expected an expression") */
  select a from one(where=(a=1));
  /* keep= restricts columns (was: silently ignored) */
  select * from two(keep=a);
  /* options on a JOINed table apply too */
  select two.a, one.a as oa from two inner join one(where=(a=2)) on two.a=one.a;
quit;
