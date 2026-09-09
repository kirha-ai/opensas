/* Protocol visit windows from first dose (INTNX week/month) */
data sv;
  input USUBJID $ RFSTDTC : $9.;
  datalines;
01-001 15JAN2024
01-002 01FEB2024
;
run;
data windows;
  set sv;
  rfst = input(RFSTDTC, date9.);
  wk4 = intnx("week", rfst, 4);
  mo3 = intnx("month", rfst, 3);
  format rfst wk4 mo3 date9.;
run;
proc print data=windows; var USUBJID rfst wk4 mo3; run;
