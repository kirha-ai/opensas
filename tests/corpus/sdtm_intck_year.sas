/* Age at first dose in whole years (INTCK year + date informats) */
data dm;
  input USUBJID $ BRTHDTC : $9. RFSTDTC : $9.;
  datalines;
01-001 15JUN1980 01MAR2024
01-002 20DEC1990 01MAR2024
;
run;
data age;
  set dm;
  brth = input(BRTHDTC, date9.);
  rfst = input(RFSTDTC, date9.);
  ageyr = intck("year", brth, rfst);
run;
proc print data=age; var USUBJID ageyr; run;
