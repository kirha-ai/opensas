/* Subjects with NO AE (SQL correlated NOT EXISTS anti-join) */
data dm;
  input USUBJID $;
  datalines;
01-001
01-002
01-003
;
run;
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 HEADACHE
01-003 RASH
;
run;
proc sql;
  select USUBJID from dm
  where not exists (select 1 from ae where ae.USUBJID = dm.USUBJID)
  order by USUBJID;
quit;
