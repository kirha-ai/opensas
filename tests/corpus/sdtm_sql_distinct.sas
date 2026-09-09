/* Distinct treatment arms present (SQL SELECT DISTINCT) */
data dm;
  input USUBJID $ ARM $;
  datalines;
01-001 DRUG
01-002 PLACEBO
01-003 DRUG
01-004 DRUG
01-005 PLACEBO
;
run;
proc sql;
  select distinct ARM from dm order by ARM;
quit;
