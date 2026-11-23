/* Pin the finite upper risk-ratio bound at the anti-diagonal with METHOD=NOSCORE. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 0
1 2 3
2 1 7
2 2 0
;
run;

ods output RelRisk1ExactCL=rr_limits;
proc freq data=sample;
  weight n / zeros;
  tables r*c / relrisk alpha=.934;
  exact relrisk(method=noscore);
run;
ods output close;
proc print data=rr_limits noobs;
  var name1 nValue1; format nValue1 best32.;
run;
