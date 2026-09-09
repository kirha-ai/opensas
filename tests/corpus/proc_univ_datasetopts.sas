/* BUG-univdatasetopts — PROC UNIVARIATE's header had no data=x(…) arm: the
   paren group hit the option catch-all, rc 1 with a degenerate empty-name
   message, on valid SAS. Now skipped as a group so procInput APPLIES it —
   the where=(age>28) filter must give N=2, not 3. */
data have;
  input name $ age;
  datalines;
Carol 40
Alice 30
Bob 25
;
run;
proc univariate data=have(where=(age>28));
  var age;
run;
