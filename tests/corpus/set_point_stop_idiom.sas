/* Language Reference: Concepts p.488 (BUG-pointnoiterate): "A DATA step that reads observations from a
   SAS data set with a SET statement that uses the POINT= option has no way to
   detect the end of the input SAS data set. ... Such a DATA step usually
   requires a STOP statement." A step that needs a STOP to end is a step that
   otherwise KEEPS ITERATING — each direct-access read drives one implicit
   iteration, so the doc's own POINT=+STOP idiom returns ALL 3 rows (it
   returned exactly 1 before the fix). The out-of-range read that a missing
   STOP would cause is pinned separately by set_point_oor (BUG-pointnobs). */
data d; input v; datalines;
10
20
30
;
run;

/* canonical form: NOBS= bounds the counter, STOP ends the step */
data b;
  p+1;
  set d point=p nobs=n;
  output;
  if p=n then stop;
run;
proc print data=b noobs; run;

/* _n_-driven form of the same idiom (the `if _error_ then stop;` guard of the
   p.488 pattern), stopped cleanly at the last obs */
data o;
  p=_n_;
  set d point=p;
  if _error_ then stop;
  output;
  if p=3 then stop;
run;
proc print data=o noobs; run;
