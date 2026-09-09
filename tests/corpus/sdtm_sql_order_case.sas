/* Order events by severity rank via ORDER BY CASE (SQL) */
data ae;
  input USUBJID $ AESEV $;
  datalines;
01-001 MILD
01-002 SEVERE
01-003 MODERATE
01-004 SEVERE
;
run;
proc sql;
  select USUBJID, AESEV from ae
  order by case AESEV when "SEVERE" then 1 when "MODERATE" then 2 else 3 end, USUBJID;
quit;
