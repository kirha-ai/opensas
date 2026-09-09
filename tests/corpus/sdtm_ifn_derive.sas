/* Responder flag via IFN + rounding (numeric helper functions) */
data resp;
  input USUBJID $ BASE POST;
  datalines;
01-001 100 70
01-002 100 95
01-003 100 60
;
run;
data flag;
  set resp;
  pchg = round(100 * (POST - BASE) / BASE, 0.1);
  respfl = ifn(pchg <= -30, 1, 0);
run;
proc print data=flag; var USUBJID pchg respfl; run;
