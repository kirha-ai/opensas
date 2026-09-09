/* Capture a computed max into a macro var, reuse it next step (SYMPUTX + &var) */
data lb; input AVAL; datalines;
10
20
30
;
run;
data _null_;
  set lb end=last;
  retain mx;
  mx = max(mx, AVAL);
  if last then call symputx("maxval", mx);
run;
data flag;
  set lb;
  pctmax = round(100 * AVAL / &maxval, 0.1);
run;
proc print data=flag; var AVAL pctmax; run;
