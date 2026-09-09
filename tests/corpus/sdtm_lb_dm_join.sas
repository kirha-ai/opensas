/* LB joined to DM demographics, ALT only (SQL inner join + where) */
data dm;
  input USUBJID $ SEX $ AGE;
  datalines;
01-001 M 45
01-002 F 52
01-003 M 38
;
run;

data lb;
  input USUBJID $ LBTESTCD $ LBSTRESN;
  datalines;
01-001 ALT 30
01-001 AST 25
01-002 ALT 45
01-003 ALT 55
;
run;

proc sql;
  select lb.USUBJID, dm.SEX, dm.AGE, lb.LBSTRESN
  from lb inner join dm on lb.USUBJID = dm.USUBJID
  where lb.LBTESTCD = "ALT"
  order by lb.USUBJID;
quit;
