/* expect-rc: 1 */
/* Request the mutually exclusive Monte Carlo and exact point probability options. */
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
  exact fisher / mc point seed=713 n=2000;
run;
