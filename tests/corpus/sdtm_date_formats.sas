/* Render one SAS date in several write formats */
data d;
  dt = "04JUL2024"d;
  length s_date $9 s_monyy $7 s_dow $9;
  s_date  = put(dt, date9.);
  s_monyy = put(dt, monyy7.);
  s_dow   = put(dt, downame9.);
run;
proc print data=d; var s_date s_monyy s_dow; run;
