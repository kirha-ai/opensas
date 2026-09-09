/* BUG-dsfnsclose: a missing/NaN or huge dsid/index must NOT panic (@intFromFloat
   aborts on NaN/inf/out-of-usize; a NaN also slips a plain `<1` guard). Every SCL
   fn routed through entry()/idx() returns its error value instead. */
data nums; input x; datalines;
10
20
30
;
run;
data _null_;
  close_nan   = close(.);
  close_huge  = close(1e30);
  close_neg   = close(-5);
  attrn_nan   = attrn(., "NOBS");
  getvarn_bad = getvarn(1e30, 1);
  d   = open("nums");
  rcf = fetch(d);
  gv_nan_n   = getvarn(d, .);
  gv_huge_n  = getvarn(d, 1e30);
  point_nan  = point(d, .);
  fobs_huge  = fetchobs(d, 1e30);
  close_ok   = close(d);
  put "close_nan="   close_nan;
  put "close_huge="  close_huge;
  put "close_neg="   close_neg;
  put "attrn_nan="   attrn_nan;
  put "getvarn_bad=" getvarn_bad;
  put "gv_nan_n="    gv_nan_n;
  put "gv_huge_n="   gv_huge_n;
  put "point_nan="   point_nan;
  put "fobs_huge="   fobs_huge;
  put "close_ok="    close_ok;
run;
