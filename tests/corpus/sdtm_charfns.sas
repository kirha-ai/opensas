/* Build a display label + clean a term (CATX / TRANWRD / SUBSTR) */
data ae;
  input USUBJID $ AETERM $20.;
  datalines;
01-001 HEAD_ACHE
01-002 NAUSEA
;
run;
data lbl;
  set ae;
  length disp $40 clean $20;
  clean = tranwrd(AETERM, "_", " ");
  disp  = catx(": ", USUBJID, clean);
  site  = substr(USUBJID, 1, 2);
run;
proc print data=lbl; var USUBJID clean disp site; run;
