/* Expose percent of table, row, column and stratum for unequal stratum totals. */
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

proc freq data=sample noprint;
  weight n;
  tables s*r*c / out=cellpct outpct outexpect;
run;
proc contents data=cellpct out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc print data=cellpct noobs;
run;
