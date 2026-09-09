/* Frequency of a derived binary completion flag */
data ds; input USUBJID $ DSDECOD : $9.; datalines;
01-001 COMPLETED
01-002 WITHDRAWN
01-003 COMPLETED
01-004 COMPLETED
01-005 WITHDRAWN
;
run;
data f;
  set ds;
  length complfl $1;
  if DSDECOD = "COMPLETED" then complfl = "Y";
  else complfl = "N";
run;
proc freq data=f; tables complfl; run;
