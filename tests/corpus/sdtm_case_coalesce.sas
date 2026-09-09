/* Derive analysis value (coalesce), flag high (CASE) in one SQL query */
data lb;
  input USUBJID $ AVAL BASE;
  datalines;
01-001 120 100
01-002 . 90
01-003 80 80
;
run;
proc sql;
  select USUBJID,
         coalesce(AVAL, BASE) as v,
         case when coalesce(AVAL, BASE) >= 100 then "HIGH" else "OK" end as flag
  from lb
  order by USUBJID;
quit;
