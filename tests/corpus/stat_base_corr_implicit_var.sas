/* Omit VAR and exclude character and FREQ columns from the default analysis. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input tag $ x y n;
  datalines;
A 1 2 1
B 2 5 3
C 3 1 2
D 4 4 1
;
run;

proc corr data=sample ;
  freq n;
run;
