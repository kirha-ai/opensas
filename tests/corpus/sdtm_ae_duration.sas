/* AE: duration in days + start month from ISO-ish dates (date functions/formats) */
data ae;
  input USUBJID $ AESTDTC : $9. AEENDTC : $9.;
  datalines;
01-001 01JAN2024 05JAN2024
01-002 10FEB2024 10FEB2024
01-003 15MAR2024 20MAR2024
;
run;

data dur;
  set ae;
  st  = input(AESTDTC, date9.);
  en  = input(AEENDTC, date9.);
  dur = en - st + 1;
  stmon = month(st);
  format st en date9.;
run;

proc print data=dur; var USUBJID st en dur stmon; run;
