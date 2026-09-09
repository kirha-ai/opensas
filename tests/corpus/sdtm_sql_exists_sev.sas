/* Subjects with at least one SEVERE AE (correlated EXISTS with a condition) */
data dm; input USUBJID $; datalines;
01-001
01-002
01-003
;
run;
data ae; input USUBJID $ AESEV $; datalines;
01-001 MILD
01-002 SEVERE
01-003 MILD
;
run;
proc sql;
  select USUBJID from dm
  where exists (select 1 from ae where ae.USUBJID = dm.USUBJID and ae.AESEV = "SEVERE")
  order by USUBJID;
quit;
