/* All subjects, labs where present (SQL LEFT JOIN → missing for none) */
data dm;
  input USUBJID $ SEX $;
  datalines;
01-001 M
01-002 F
01-003 M
;
run;

data lb;
  input USUBJID $ LBSTRESN;
  datalines;
01-001 30
01-003 55
;
run;

proc sql;
  select dm.USUBJID, dm.SEX, lb.LBSTRESN
  from dm left join lb on dm.USUBJID = lb.USUBJID
  order by dm.USUBJID;
quit;
