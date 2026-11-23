/* OUTPLS has a continuous VAR, ordinal WITH, and an interior correlation. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x g;
  datalines;
1 1
3 1
5 1
2 2
4 2
6 2
3 3
5 3
8 3
;
run;

proc corr data=sample polyserial outpls=serial noprint;
  var x;
  with g;
run;
proc contents data=serial out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc print data=serial noobs;
run;
