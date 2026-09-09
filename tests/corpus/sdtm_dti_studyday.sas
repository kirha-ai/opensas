/* Study day + weeks-on-study from a reference start (date arithmetic + INT) */
data ae; input USUBJID $ RFSTDTC $ AESTDTC $; datalines;
01-001 10JAN2024 24JAN2024
01-002 10JAN2024 10JAN2024
01-003 10JAN2024 05JAN2024
;
run;
data d;
  set ae;
  rf = input(RFSTDTC, date9.);
  ae = input(AESTDTC, date9.);
  if ae >= rf then aedy = ae - rf + 1;
  else aedy = ae - rf;
  wk = int((aedy - 1) / 7) + 1;
  keep USUBJID aedy wk;
run;
proc print data=d; run;
