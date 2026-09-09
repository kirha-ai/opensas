/* AE count per subject including those with none (LEFT JOIN + count) */
data dm; input USUBJID $; datalines;
01-001
01-002
01-003
;
run;
data ae; input USUBJID $ AETERM $; datalines;
01-001 A
01-001 B
01-003 C
;
run;
proc sql;
  select dm.USUBJID, count(ae.AETERM) as naes
  from dm left join ae on dm.USUBJID = ae.USUBJID
  group by dm.USUBJID
  order by dm.USUBJID;
quit;
