/* Nested CASE assigning a CTCAE-style grade band (SQL) */
data lb; input USUBJID $ RATIO; datalines;
01-001 0.8
01-002 2.5
01-003 4.0
01-004 6.0
;
run;
proc sql;
  select USUBJID,
    case when RATIO <= 1 then "G0"
         else case when RATIO <= 3 then "G1"
                   else case when RATIO <= 5 then "G2" else "G3" end
              end
    end as grade
  from lb
  order by USUBJID;
quit;
