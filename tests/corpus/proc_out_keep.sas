data d;
  input usubjid $ visitnum visit $ svstdtc : $10. extra;
  datalines;
S01 1 SCR 2020-01-01 99
S01 2 BL 2020-01-15 88
S02 1 SCR 2020-02-01 77
;
run;
proc sort data=d out=sv(keep=usubjid visitnum visit svstdtc); by usubjid visitnum; run;
proc print data=sv noobs; run;
proc sort data=d out=dr(drop=extra svstdtc); by usubjid; run;
proc print data=dr noobs; run;
proc sort data=d out=rn(keep=usubjid extra rename=(extra=flag)); by usubjid; run;
proc print data=rn noobs; run;
proc contents data=d out=c(keep=name type) noprint; run;
proc sort data=c out=c2; by name; run;
proc print data=c2 noobs; run;
