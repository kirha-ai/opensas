/* Compound WHERE (AND / OR) selecting treatment-emergent severe events */
data ae;
  input USUBJID $ AESEV $ TRTEMFL $;
  datalines;
01-001 SEVERE Y
01-002 MILD Y
01-003 SEVERE N
01-004 MODERATE Y
;
run;
proc print data=ae;
  where TRTEMFL = "Y" and (AESEV = "SEVERE" or AESEV = "MODERATE");
run;
