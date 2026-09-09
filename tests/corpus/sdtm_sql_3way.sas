/* Three-table inner join (DM + LB + VS) on subject */
data dm; input USUBJID $ SEX $; datalines;
01-001 M
01-002 F
;
run;
data lb; input USUBJID $ ALT; datalines;
01-001 30
01-002 45
;
run;
data vs; input USUBJID $ SBP; datalines;
01-001 120
01-002 130
;
run;
proc sql;
  select dm.USUBJID, dm.SEX, lb.ALT, vs.SBP
  from dm
    inner join lb on dm.USUBJID = lb.USUBJID
    inner join vs on dm.USUBJID = vs.USUBJID
  order by dm.USUBJID;
quit;
