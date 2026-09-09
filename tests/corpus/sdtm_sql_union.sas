/* Pooled unique AE terms from two sources (SQL UNION dedups) */
data ae1;
  input USUBJID $ AETERM $;
  datalines;
01-001 HEADACHE
01-002 NAUSEA
;
run;
data ae2;
  input USUBJID $ AETERM $;
  datalines;
01-002 NAUSEA
01-003 RASH
;
run;
proc sql;
  select USUBJID, AETERM from ae1
  union
  select USUBJID, AETERM from ae2
  order by USUBJID, AETERM;
quit;
