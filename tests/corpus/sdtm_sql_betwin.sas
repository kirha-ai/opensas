/* Adults at post-baseline visits (WHERE BETWEEN + IN) */
data lb; input USUBJID $ AGE VISIT $; datalines;
01-001 25 SCREEN
01-002 45 WEEK4
01-003 70 SCREEN
01-004 55 WEEK8
;
run;
proc sql;
  select USUBJID, AGE, VISIT from lb
  where AGE between 40 and 65 and VISIT in ("WEEK4", "WEEK8")
  order by USUBJID;
quit;
