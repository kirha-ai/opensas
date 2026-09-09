/* AE count per subject via correlated scalar subquery in the select list */
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 A
01-001 B
01-002 C
;
run;
data dm;
  input USUBJID $;
  datalines;
01-001
01-002
01-003
;
run;
proc sql;
  select USUBJID,
         (select count(*) from ae where ae.USUBJID = dm.USUBJID) as naes
  from dm
  order by USUBJID;
quit;
