/* BUG-univmu0freq: PROC UNIVARIATE MU0= and FREQ were silently ignored (HIGH,
   silent-wrong for clinical one-sample tests / frequency-weighted stats).
   MU0=5 makes the Tests for Location test against 5 (header "Mu0=5"); FREQ f
   weights each obs by trunc(f) so N=Sum Weights=Sum(f) and every moment is over
   the expanded sample. This fixture pins both against SAS 9.4. */
data d;
  input x f @@;
  datalines;
1 2 2 3 3 1
;
run;

/* FREQ: N = 2+3+1 = 6, Sum Obs = 1*2 + 2*3 + 3*1 = 11, Mean = 11/6. */
proc univariate data=d;
  freq f;
  var x;
run;

/* MU0=5 one-sample location tests against a nonzero reference. */
data e;
  input y @@;
  datalines;
5.0 5.2 5.4 5.6 5.8 6.0
;
run;

proc univariate data=e mu0=5;
  var y;
run;
