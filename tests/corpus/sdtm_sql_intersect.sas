/* Subjects both enrolled AND dosed (SQL INTERSECT) */
data enrolled;
  input USUBJID $;
  datalines;
01-001
01-002
01-003
;
run;
data dosed;
  input USUBJID $;
  datalines;
01-002
01-003
01-004
;
run;
proc sql;
  select USUBJID from enrolled
  intersect
  select USUBJID from dosed
  order by USUBJID;
quit;
