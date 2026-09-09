/* Min and max captured to two macro vars, used to compute a normalized score */
data vs; input AVAL; datalines;
100
150
120
180
;
run;
data _null_;
  set vs end=last;
  retain lo hi;
  if _n_ = 1 then do; lo = AVAL; hi = AVAL; end;
  lo = min(lo, AVAL);
  hi = max(hi, AVAL);
  if last then do;
    call symputx("vmin", lo);
    call symputx("vmax", hi);
  end;
run;
data norm;
  set vs;
  score = round((AVAL - &vmin) / (&vmax - &vmin), 0.01);
run;
proc print data=norm; var AVAL score; run;
