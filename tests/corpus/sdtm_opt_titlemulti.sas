/* Multiple TITLE lines stack above the listing */
title1 "Protocol PROTO-01";
title2 "Table 14.1: Demographics";
data dm;
  input USUBJID $ AGE;
  datalines;
01-001 45
01-002 52
;
run;
proc print data=dm; run;
