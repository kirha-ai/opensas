/* Cumulative columns on a one-way table with a nonalphabetic input order. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input kind $ n;
  datalines;
Z 2
A 3
M 1
;
run;

proc freq data=sample noprint order=data;
  weight n;
  tables kind / out=levels outcum;
run;
proc contents data=levels out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc print data=levels noobs;
run;
