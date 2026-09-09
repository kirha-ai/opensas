/* Numeric macro var (SYMPUTX) used in later arithmetic */
data _null_;
  call symputx("factor", 2.5);
run;
data d;
  input dose;
  adjusted = dose * &factor;
  datalines;
10
20
40
;
run;
proc print data=d; var dose adjusted; run;
