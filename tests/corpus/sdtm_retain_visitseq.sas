/* Sequential visit number within subject (RETAIN counter reset per BY group) */
data vs;
  input USUBJID $ VSDTC : $9.;
  datalines;
01-001 01JAN2024
01-001 15JAN2024
01-001 01FEB2024
01-002 10JAN2024
01-002 20JAN2024
;
run;
proc sort data=vs; by USUBJID VSDTC; run;
data seq;
  set vs;
  by USUBJID;
  retain vseq;
  if first.USUBJID then vseq = 0;
  vseq + 1;
run;
proc print data=seq; var USUBJID VSDTC vseq; run;
