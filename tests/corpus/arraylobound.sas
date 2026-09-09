/* ARRAY-lobound-impl: explicit array lower bound `array a{lo:hi} ...`. SAS 9.4:
   "you can use any integer to specify the bounds ... the lower bound defaults to
   1." Element access is offset by the lower bound, and dim/lbound/hbound honor it.
   Synthesized (no PHI). */
data t;
  array a{5:10} x5-x10;
  a{5}  = 100;   /* first element */
  a{7}  = 300;
  a{10} = 600;   /* last element */

  lo = lbound(a);   /* 5  */
  hi = hbound(a);   /* 10 */
  n  = dim(a);      /* 6  */

  /* iterate with a lower-bound-based loop; sum() skips the unset (missing) slots */
  tot = 0;
  do i = lbound(a) to hbound(a);
    tot + a{i};
  end;

  put "x5=" x5 " x7=" x7 " x10=" x10;
  put "lo=" lo " hi=" hi " n=" n " tot=" tot;
  keep x5 x7 x10 lo hi n tot;
run;

proc print data=t noobs; run;
