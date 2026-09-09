/* Missing values propagate through change-from-baseline arithmetic */
data lb; input USUBJID $ BASE POST; datalines;
01-001 100 80
01-002 . 90
01-003 100 .
;
run;
data chg;
  set lb;
  chg  = POST - BASE;
  pchg = 100 * (POST - BASE) / BASE;
run;
proc print data=chg; var USUBJID BASE POST chg pchg; run;
