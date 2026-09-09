/* Pool all lab records from two visits, keeping duplicates (UNION ALL) */
data v1;
  input USUBJID $ LBSTRESN;
  datalines;
01-001 30
01-002 45
;
run;
data v2;
  input USUBJID $ LBSTRESN;
  datalines;
01-001 30
01-003 55
;
run;
proc sql;
  select USUBJID, LBSTRESN from v1
  union all
  select USUBJID, LBSTRESN from v2
  order by USUBJID, LBSTRESN;
quit;
