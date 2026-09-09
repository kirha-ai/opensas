/* Distinct subjects per arm (grouped count(distinct)) */
data ae; input ARM $ USUBJID $; datalines;
DRUG 01-001
DRUG 01-001
DRUG 01-002
PLACEBO 01-003
;
run;
proc sql;
  select ARM, count(distinct USUBJID) as nsubj
  from ae
  group by ARM
  order by ARM;
quit;
