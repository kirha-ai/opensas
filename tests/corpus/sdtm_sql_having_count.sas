/* Subjects with more than one AE (SQL group by + HAVING count) */
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 A
01-001 B
01-001 C
01-002 D
01-003 E
01-003 F
;
run;
proc sql;
  select USUBJID, count(*) as naes
  from ae
  group by USUBJID
  having count(*) > 1
  order by USUBJID;
quit;
