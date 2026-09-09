/* Visit-month window start/middle/end via INTNX alignment (b/m/e) */
data sv; input USUBJID $ VISDTC : $9.; datalines;
01-001 15JAN2024
01-002 20FEB2024
;
run;
data d;
  set sv;
  vd = input(VISDTC, date9.);
  wstart = intnx("month", vd, 0, "b");
  wmid   = intnx("month", vd, 0, "m");
  wend   = intnx("month", vd, 0, "e");
  format vd wstart wmid wend date9.;
run;
proc print data=d; var USUBJID wstart wmid wend; run;
