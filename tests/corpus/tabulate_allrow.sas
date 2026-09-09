/* GAP-tabulateforms #8: an ALL-only row dimension. Base SAS 9.4 Procedures
   Guide printed p.2547 (pdf 2596): "If two dimensions are specified, then the
   left dimension expression defines rows, and the right dimension expression
   defines columns", and ALL is a documented dimension element ("the universal
   class variable ALL summarizes all of the categories for class variables in
   the same parenthetical group or dimension"). So `table all, v*sum` is one
   grand-total row — it used to die "no TABLE row variable" (rc 2). */
data d;
  input g $ c $ v;
datalines;
x p 1
x q 2
y p 3
;
run;
/* one grand-total row, one statistic column. */
proc tabulate data=d; class g c; var v; table all, v*sum; run;
/* the same with a class crossing in the column dimension: one All row × the
   column levels — the row must not double (the level group IS the All row). */
proc tabulate data=d; class g c; var v; table all, c*v*sum; run;
/* several statistics over the single grand-total row. */
proc tabulate data=d; class g; var v; table all, v*(sum mean n); run;
