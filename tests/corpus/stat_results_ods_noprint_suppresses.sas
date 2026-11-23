/* Record whether procedure-level NOPRINT creates a requested ODS table. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y z n;
  datalines;
1 8 4 1
2 6 1 2
2 6 5 1
3 2 2 1
4 5 6 3
5 3 2 1
6 1 5 2
8 4 8 1
9 1 3 1
;
run;

ods output PearsonCorr=hidden_corr;
proc corr data=sample noprint;
  var x y;
run;
ods output close;
data _null_;
  file print;
  present=exist("work.hidden_corr");
  put "ODS table exists=" present;
run;
