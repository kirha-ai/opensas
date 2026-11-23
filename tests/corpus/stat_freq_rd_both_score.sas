/* Compare exact risk difference bounds for complementary columns using SCORE. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 1
1 2 4
2 1 3
2 2 2
;
run;

proc freq data=sample;
  weight n / zeros;
  tables r*c / riskdiff alpha=.10;
  exact riskdiff(method=score column=both);
run;
