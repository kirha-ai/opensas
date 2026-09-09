/* Ever-abnormal flag per subject (RETAIN a 0/1 flag across BY group) */
data lb;
  input USUBJID $ VISITNUM ABNFL $;
  datalines;
01-001 1 N
01-001 2 Y
01-001 3 N
01-002 1 N
01-002 2 N
;
run;
proc sort data=lb; by USUBJID VISITNUM; run;
data ever;
  set lb;
  by USUBJID;
  retain everab;
  if first.USUBJID then everab = 0;
  if ABNFL = "Y" then everab = 1;
  if last.USUBJID then output;
  keep USUBJID everab;
run;
proc print data=ever; run;
