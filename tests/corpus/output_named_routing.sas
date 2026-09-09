/* BUG-outputundeclared non-regression: named `output <name>;` must still route
   to any dataset the DATA statement declared, matched CASE-INSENSITIVELY, incl.
   the primary. A bare `output;` fans to every declared dataset. (Only an
   UNdeclared name is now the loud ERROR — that path halts the step and cannot
   appear in a green stdout fixture, so it lives in the tick166 findings .md.) */
data lo hi;
  input v;
  if v < 10 then output LO;   /* case-insensitive: LO -> lo (primary) */
  else output Hi;             /* Hi -> hi (declared extra) */
  datalines;
5
15
8
20
;
run;
proc print data=lo; run;
proc print data=hi; run;

/* bare output; fans to BOTH declared datasets */
data a b;
  input v;
  output;
  datalines;
1
2
;
run;
proc print data=a; run;
proc print data=b; run;
