/* Capture the last subject's id into a macro var (BY-group symput) */
data dm;
  input USUBJID $ AGE;
  datalines;
01-001 45
01-002 52
01-003 38
;
run;
data _null_;
  set dm end=last;
  if last then call symputx("lastsubj", USUBJID);
run;
data note;
  length msg $30;
  msg = catx(" ", "Last enrolled:", "&lastsubj");
run;
proc print data=note; run;
