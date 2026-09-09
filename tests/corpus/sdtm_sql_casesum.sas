/* Severity crosstab per arm via sum(CASE) (SQL) */
data ae; input ARM $ AESEV $; datalines;
DRUG MILD
DRUG SEVERE
DRUG SEVERE
PLACEBO MILD
;
run;
proc sql;
  select ARM,
    sum(case when AESEV = "MILD" then 1 else 0 end) as mild,
    sum(case when AESEV = "SEVERE" then 1 else 0 end) as severe
  from ae
  group by ARM
  order by ARM;
quit;
