/* One SAS date rendered under several write formats */
data d;
  dt = "04JUL2024"d;
  length s1 $9 s2 $10 s3 $10 s4 $10 s5 $7;
  s1 = put(dt, date9.);
  s2 = put(dt, yymmdd10.);
  s3 = put(dt, mmddyy10.);
  s4 = put(dt, ddmmyy10.);
  s5 = put(dt, monyy7.);
run;
proc print data=d; var s1 s2 s3 s4 s5; run;
