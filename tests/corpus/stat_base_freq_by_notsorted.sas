/* Repeated noncontiguous BY values create separate runs under NOTSORTED. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input g $ x;
  datalines;
B 1
B 2
A 1
B 3
;
run;

proc freq data=sample;
  by g notsorted;
  tables x;
run;
