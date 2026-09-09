/* Read dates in several informats to the same SAS date value */
data raw;
  input src1 : $10. src2 : $10. src3 : $10.;
  datalines;
01/15/2024 15/01/2024 2024-01-15
;
run;
data d;
  set raw;
  d1 = input(src1, mmddyy10.);
  d2 = input(src2, ddmmyy10.);
  d3 = input(src3, yymmdd10.);
  same = (d1 = d2) and (d2 = d3);
run;
proc print data=d; var d1 d2 d3 same; run;
