/* Per-arm peak from an inline derived table, then filter (SQL FROM subquery) */
data vs; input ARM $ USUBJID $ AVAL; datalines;
DRUG 01-001 120
DRUG 01-002 145
PLACEBO 01-003 138
PLACEBO 01-004 150
;
run;
proc sql;
  select ARM, peak
  from (select ARM, max(AVAL) as peak from vs group by ARM)
  where peak > 140
  order by ARM;
quit;
