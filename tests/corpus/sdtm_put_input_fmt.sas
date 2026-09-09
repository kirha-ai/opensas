/* Date round-trip (date9. in, yymmdd10. out) + numeric-to-char (PUT/INPUT) */
data vs;
  input USUBJID $ VSSTRESN VSDTC : $9.;
  datalines;
01-001 120 15JAN2024
01-002 135 20FEB2024
;
run;
data fmt;
  set vs;
  length dtc $10 cat $6;
  dt  = input(VSDTC, date9.);
  dtc = put(dt, yymmdd10.);
  cat = put(VSSTRESN, 5.1);
  format dt date9.;
run;
proc print data=fmt; var USUBJID dt dtc cat; run;
