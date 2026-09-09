/* Each arm's peak subject (value equals the arm's max — correlated subquery) */
data lb; input ARM $ USUBJID $ AVAL; datalines;
DRUG 01-001 30
DRUG 01-002 55
PLACEBO 01-003 40
PLACEBO 01-004 20
;
run;
proc sql;
  select ARM, USUBJID, AVAL
  from lb x
  where AVAL = (select max(AVAL) from lb y where y.ARM = x.ARM)
  order by ARM;
quit;
