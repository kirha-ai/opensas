/* Subjects above their OWN arm's mean (SQL correlated subquery) */
data vs;
  input ARM $ USUBJID $ VSSTRESN;
  datalines;
DRUG 01-001 120
DRUG 01-002 140
PLACEBO 01-003 110
PLACEBO 01-004 130
;
run;
proc sql;
  select ARM, USUBJID, VSSTRESN
  from vs x
  where VSSTRESN > (select avg(VSSTRESN) from vs y where y.ARM = x.ARM)
  order by ARM, USUBJID;
quit;
