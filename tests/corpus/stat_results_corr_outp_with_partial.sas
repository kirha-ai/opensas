/* Record OUTP row and column identities for a partial rectangular matrix. */
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

proc corr data=sample noprint outp=part;
  var x;
  with y;
  partial z;
run;
proc contents data=part out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc print data=part noobs;
run;
