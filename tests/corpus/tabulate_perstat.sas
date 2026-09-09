/* GAP-tabulateforms #7: per-element stat lists. The concatenation (blank)
   operator gives EACH column element its own statistics — Base SAS 9.4
   Procedures Guide printed p.2548 (pdf 2597): blank "places the output for
   each element immediately after the output for the preceding element". The
   old flat stat list unioned every element's statistics onto the LAST
   analysis variable: `a*sum b*mean` rendered b×(Sum,Mean) at exit 0 — an
   extra unrequested column and a*sum silently dropped, a wrong table with
   no diagnostic. These tables pin the rendered columns, so the fixture
   fails if the extra columns ever come back. */
data d;
  input r $ a b;
datalines;
x 1 10
x 2 20
y 3 30
;
run;
/* two var blocks, one stat each: a-Sum then b-Mean — never b×(Sum,Mean). */
proc tabulate data=d; class r; var a b; table r, a*sum b*mean; run;
/* a parenthesised stat list binds to ITS element: a×(Sum,N) then b-Mean. */
proc tabulate data=d; class r; var a b; table r, a*(sum n) b*mean; run;
/* a bare analysis var concatenated with a crossed one: default SUM
   (p.2547: "For analysis variables, the default statistic is SUM."). */
proc tabulate data=d; class r; var a b; table r, a b*mean; run;
