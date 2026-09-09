/* Change vs previous and vs two visits back (DIF/DIF2) */
data vs;
  input VISITNUM AVAL;
  datalines;
1 100
2 110
3 130
4 125
;
run;
data d;
  set vs;
  chg1 = dif(AVAL);
  chg2 = dif2(AVAL);
run;
proc print data=d; var VISITNUM AVAL chg1 chg2; run;
