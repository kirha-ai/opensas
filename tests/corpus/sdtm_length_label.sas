/* FORMAT statement applies formatted values in PROC PRINT (date9. + 6.1) */
data lb;
  input USUBJID $ LBSTRESN LBDT;
  datalines;
01-001 30 22000
01-002 45 22010
;
run;
data lbl;
  set lb;
  label LBSTRESN = "Result (U/L)" LBDT = "Collection Date";
  format LBDT date9. LBSTRESN 6.1;
run;
proc print data=lbl;
  var USUBJID LBSTRESN LBDT;
run;
