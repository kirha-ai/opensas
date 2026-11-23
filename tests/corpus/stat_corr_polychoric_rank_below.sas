/* Nested ordinal levels with frequencies scaled by 11; inspect correlation, SE and test statistics at full precision. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y f;
  datalines;
0 0 110
0 1 352
10 1 418
20 1 110
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
