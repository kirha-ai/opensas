/* There are two marginal levels and no discordant pairs. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 3
1 2 0
2 1 0
2 2 4
;
run;

proc freq data=sample;
  weight n / zeros;
  tables r*c;
  exact mcnem;
run;
