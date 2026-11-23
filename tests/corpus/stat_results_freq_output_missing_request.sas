/* Request OUTPUT FISHER without asking the procedure to compute Fisher statistics. */
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

proc freq data=sample noprint;
  weight n;
  tables r*c;
  output out=notrequested fisher;
run;
data _null_;
  file print;
  present=exist("work.notrequested");
  put "OUTPUT data set exists=" present;
run;
