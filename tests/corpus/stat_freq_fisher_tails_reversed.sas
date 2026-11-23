/* Swapping columns exchanges one-sided Fisher tails at fixed two-sided significance. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 4
1 2 1
2 1 2
2 2 3
;
run;

proc freq data=sample;
  weight n / zeros;
  tables r*c;
  exact fisher / point midp;
run;
