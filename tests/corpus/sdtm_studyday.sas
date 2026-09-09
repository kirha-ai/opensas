/* Study day (--DY) from a reference start date (SAS: no day 0) */
data ae;
  input USUBJID $ RFSTDTC $ AESTDTC $;
  datalines;
01-001 10JAN2024 15JAN2024
01-002 10JAN2024 10JAN2024
01-003 10JAN2024 05JAN2024
;
run;
data d;
  set ae;
  rfst = input(RFSTDTC, date9.);
  aest = input(AESTDTC, date9.);
  if aest >= rfst then aedy = aest - rfst + 1;
  else aedy = aest - rfst;
run;
proc print data=d; var USUBJID aedy; run;
