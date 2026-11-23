/* Coalesce two internal values sharing a format; observe level order and missing placement. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input code n;
  datalines;
20 1
10 3
11 2
30 4
. 1
;
run;
proc format;
  value bandfmt 10,11="Zulu" 20="Alpha" 30="Middle";
run;

proc freq data=sample order=data;
  format code bandfmt.;
  weight n;
  tables code / missing;
run;
