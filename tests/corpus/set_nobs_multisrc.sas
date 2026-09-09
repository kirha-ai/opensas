data a;
  input x;
  datalines;
10
20
30
;
run;

data b;
  input x;
  datalines;
40
50
;
run;

/* GAP-nobsmultisrc: nobs= over multiple SET sources is the a+b TOTAL (5),
   known before the step iterates — not the per-source count. */
data _null_;
  set a b nobs=n;
  if _n_=1 then put n=;
run;
