/* Use two 2x2 strata with opposite sample odds ratios. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input s r c n;
  datalines;
1 1 1 1
1 1 2 3
1 2 1 3
1 2 2 1
2 1 1 2
2 1 2 1
2 2 1 1
2 2 2 3
;
run;

proc freq data=sample;
  weight n / zeros;
  tables s*r*c;
  exact comor;
run;
