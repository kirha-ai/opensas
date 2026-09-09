/* Months from first dose to AE onset (intck) + AE onset + 30d window (intnx) */
data ae;
  input USUBJID $ RFSTDTC : $9. AESTDTC : $9.;
  datalines;
01-001 01JAN2024 15FEB2024
01-002 01JAN2024 20MAR2024
01-003 01JAN2024 05JAN2024
;
run;

data aew;
  set ae;
  rfst = input(RFSTDTC, date9.);
  aest = input(AESTDTC, date9.);
  mo   = intck("month", rfst, aest);
  win  = intnx("day", aest, 30);
  format win date9.;
run;

proc print data=aew; var USUBJID mo win; run;
