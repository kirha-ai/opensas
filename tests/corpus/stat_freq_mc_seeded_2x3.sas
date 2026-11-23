/* Fixed seed, nondefault sample count and confidence level on a nondegenerate 2x3 table. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 3
1 2 1
1 3 0
2 1 0
2 2 2
2 3 2
;
run;

proc freq data=sample;
  weight n / zeros;
  tables r*c;
  exact fisher / mc seed=713 n=2000 alpha=.05;
run;
