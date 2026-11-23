/* Exclude Moments from the listing while routing its data to ODS OUTPUT. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x @@;
  datalines;
0.12 0.23 0.31 0.48 0.52 0.76 0.87 1.03 1.29 1.36 1.70 2.28 2.74 3.52 4.85 6.21
;
run;

ods listing exclude Moments;
ods output Moments=captured_moments;
proc univariate data=sample; var x; run;
ods output close;
ods listing exclude none;
proc print data=captured_moments noobs;
run;
