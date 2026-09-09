/* Subjects above their own arm's mean (correlated subquery in WHERE) */
data vs; input ARM $ USUBJID $ AVAL; datalines;
DRUG 01-001 110
DRUG 01-002 130
PLACEBO 01-003 140
PLACEBO 01-004 160
;
run;
proc sql;
  select ARM, USUBJID, AVAL
  from vs x
  where AVAL > (select avg(AVAL) from vs y where y.ARM = x.ARM)
  order by ARM;
quit;
