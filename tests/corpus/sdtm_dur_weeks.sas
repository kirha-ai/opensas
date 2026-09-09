/* Exposure duration in days and whole weeks (date diff + INT) */
data ex;
  input USUBJID $ EXSTDTC $ EXENDTC $;
  datalines;
01-001 01JAN2024 21JAN2024
01-002 10FEB2024 24FEB2024
;
run;
data d;
  set ex;
  st = input(EXSTDTC, date9.);
  en = input(EXENDTC, date9.);
  durdays  = en - st + 1;
  durweeks = int(durdays / 7);
run;
proc print data=d; var USUBJID durdays durweeks; run;
