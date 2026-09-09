/* Grade lab values against the normal range (SQL CASE) */
data lb;
  input USUBJID $ LBSTRESN LBORNRLO LBORNRHI;
  datalines;
01-001 30 10 40
01-002 5 10 40
01-003 50 10 40
;
run;
proc sql;
  select USUBJID, LBSTRESN,
    case when LBSTRESN < LBORNRLO then "LOW"
         when LBSTRESN > LBORNRHI then "HIGH"
         else "NORMAL" end as grade
  from lb
  order by USUBJID;
quit;
