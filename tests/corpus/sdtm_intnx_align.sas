/* Month-window start and end via INTNX begin/end alignment */
data sv;
  input USUBJID $ VISDTC : $9.;
  datalines;
01-001 15JAN2024
01-002 20FEB2024
;
run;
data d;
  set sv;
  vd = input(VISDTC, date9.);
  mstart = intnx("month", vd, 0, "b");
  mend   = intnx("month", vd, 0, "e");
  format vd mstart mend date9.;
run;
proc print data=d; var USUBJID mstart mend; run;
