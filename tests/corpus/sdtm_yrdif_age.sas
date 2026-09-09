/* Age at consent in years with YRDIF ('AGE' basis) */
data dm;
  input USUBJID $ BRTHDTC : $9. RFICDTC : $9.;
  datalines;
01-001 15JUN1980 15JAN2024
01-002 20DEC1990 15JAN2024
01-003 01JAN2000 31DEC2023
;
run;
data d;
  set dm;
  brth = input(BRTHDTC, date9.);
  ric  = input(RFICDTC, date9.);
  age  = floor(yrdif(brth, ric, "AGE"));
run;
proc print data=d; var USUBJID age; run;
