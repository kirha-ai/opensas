/* Cell rows and the one-row chi-square result describe the final request in a multi-table statement. */
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

proc freq data=sample noprint;
  weight n;
  tables r c r*c / out=lastcells chisq;
  output out=laststats pchi;
run;
proc print data=lastcells noobs;
run;
proc contents data=laststats out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc print data=laststats noobs;
run;
