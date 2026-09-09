/* Three-tier grade from a lab ratio (nested CASE in SQL) */
data lb; input USUBJID $ RATIO; datalines;
01-001 0.5
01-002 2.0
01-003 4.0
;
run;
proc sql;
  select USUBJID,
    case when RATIO < 1 then "LOW"
         else case when RATIO < 3 then "MID" else "HIGH" end
    end as cat
  from lb
  order by USUBJID;
quit;
