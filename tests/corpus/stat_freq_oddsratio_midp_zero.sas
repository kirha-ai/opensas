/* A zero corner gives a boundary odds ratio and a finite upper mid-p limit. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 0
1 2 3
2 1 2
2 2 4
;
run;

proc freq data=sample;
  weight n / zeros;
  tables r*c / or(cl=midp);
run;
