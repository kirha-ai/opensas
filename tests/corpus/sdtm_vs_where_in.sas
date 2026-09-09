/* Select target visits with a WHERE IN-list, summarize (SQL) */
data vs;
  input USUBJID $ VISIT $ VSSTRESN;
  datalines;
01-001 SCREEN 118
01-001 WEEK4 122
01-001 WEEK8 120
01-002 SCREEN 130
01-002 WEEK4 128
01-002 WEEK8 126
;
run;

proc sql;
  select VISIT, count(*) as n, avg(VSSTRESN) as mean
  from vs
  where VISIT in ("WEEK4", "WEEK8")
  group by VISIT
  order by VISIT;
quit;
