/* Vitals above the overall mean (SQL scalar subquery) */
data vs;
  input USUBJID $ VSSTRESN;
  datalines;
01-001 120
01-002 140
01-003 110
01-004 150
;
run;

proc sql;
  select USUBJID, VSSTRESN
  from vs
  where VSSTRESN > (select avg(VSSTRESN) from vs)
  order by USUBJID;
quit;
