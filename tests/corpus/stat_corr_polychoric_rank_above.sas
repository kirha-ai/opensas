/* Nested ordinal levels with frequencies scaled by 12; inspect correlation, SE and test statistics at full precision. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y f;
  datalines;
0 0 120
0 1 384
10 1 456
20 1 120
;
run;

ods output PolychoricCorr=boundary_fit;
proc corr data=sample polychoric(converge=1e-6);
  var x;
  with y;
  freq f;
run;
ods output close;
proc print data=boundary_fit noobs;
  format _numeric_ best32.;
run;
