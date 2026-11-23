/* Create independent ODS tables for two different rank methods in one procedure. */
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

ods output SpearmanCorr=spearman_tab KendallCorr=kendall_tab;
proc corr data=sample spearman kendall;
  var x y;
run;
ods output close;
proc print data=spearman_tab noobs;
run;
proc print data=kendall_tab noobs;
run;
