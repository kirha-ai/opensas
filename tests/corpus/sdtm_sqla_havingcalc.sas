/* HAVING on a CALCULATED aggregate alias */
data ae; input USUBJID $ n; datalines;
01-001 3
01-001 2
01-002 1
;
run;
proc sql;
  select USUBJID, sum(n) as total from ae group by USUBJID having calculated total >= 5;
quit;
