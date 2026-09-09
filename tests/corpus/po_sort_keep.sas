data sv;
  length usubjid $4 visit $4 svstdtc $10;
  input usubjid $ visitnum visit $ svstdtc $ extra;
  datalines;
S01 1 SCR 2020-01-01 99
S01 2 BL 2020-01-15 88
S02 1 SCR 2020-02-01 77
;
run;
proc sort data=sv out=svo(keep=usubjid visitnum visit svstdtc); by usubjid visitnum; run;
proc print data=svo noobs; run;
