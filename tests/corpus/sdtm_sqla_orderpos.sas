/* ORDER BY select-list position */
data lb; input USUBJID $ AVAL; datalines;
01-003 30
01-001 55
01-002 45
;
run;
proc sql;
  select USUBJID, AVAL from lb order by 2 desc;
quit;
