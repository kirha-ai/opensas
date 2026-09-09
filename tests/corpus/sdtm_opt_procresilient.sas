/* An unsupported PROC between steps errors (stderr) but the run continues
   expect-rc: 2 */
data first;
  input USUBJID $ AVAL;
  datalines;
01-001 10
;
run;
proc unsupportedproc data=first; run;
data second;
  set first;
  doubled = AVAL * 2;
run;
proc print data=second; run;
