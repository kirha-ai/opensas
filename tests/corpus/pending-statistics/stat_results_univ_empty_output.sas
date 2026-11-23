/* Check count, missing value and descriptor behavior with zero input rows. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  length x 8; stop;
run;

proc univariate data=sample noprint;
  var x; output out=empty_stats n=n mean=m;
run;
proc contents data=empty_stats out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc sql; select count(*) as rows from empty_stats; quit;
proc print data=empty_stats noobs;
run;
