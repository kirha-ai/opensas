/* MOD for even/odd cohort assignment; INT for whole units */
data dm;
  input USUBJID $ SEQ;
  datalines;
01-001 1
01-002 2
01-003 3
01-004 4
;
run;
data d;
  set dm;
  cohort = mod(SEQ, 2);
  pair   = int((SEQ + 1) / 2);
run;
proc print data=d; var USUBJID SEQ cohort pair; run;
