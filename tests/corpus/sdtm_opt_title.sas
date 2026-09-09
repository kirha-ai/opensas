/* TITLE and FOOTNOTE frame a clinical listing (PROC PRINT) */
title "Adverse Events Listing";
footnote "Study PROTO-01 - Confidential";
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 HEADACHE
01-002 NAUSEA
;
run;
proc print data=ae; run;
