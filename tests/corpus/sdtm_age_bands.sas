/* Age at baseline + banding (arithmetic + nested IF) */
data dm;
  input USUBJID $ BRTHDTC : $9.;
  datalines;
01-001 15JUN1955
01-002 20DEC1990
01-003 01JAN2010
;
run;
data d;
  set dm;
  brth = input(BRTHDTC, date9.);
  age  = floor(yrdif(brth, "01JAN2024"d, "AGE"));
  length band $6;
  if age < 18 then band = "PED";
  else if age < 65 then band = "ADULT";
  else band = "SENIOR";
run;
proc print data=d; var USUBJID age band; run;
