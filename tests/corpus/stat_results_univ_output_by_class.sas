/* Retain BY and CLASS variables and their attributes in OUTPUT OUT=. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  length site $4 arm $6; label arm="Treatment arm";
  input site $ arm $ x;
  datalines;
A C 1
A T 5
A C 3
B T 4
B T 8
;
run;

proc univariate data=sample noprint;
  by site; class arm; var x;
  output out=byclass n=n mean=average;
run;
proc contents data=byclass out=columns(keep=varnum name type length label format) noprint; run;
proc sort data=columns; by varnum; run;
proc print data=columns noobs;
  var varnum name type length format label;
run;
proc print data=byclass noobs;
run;
