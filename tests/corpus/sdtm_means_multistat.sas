/* Full stat panel per lab test to a dataset (PROC MEANS OUTPUT NWAY) */
data lb; input LBTESTCD $ AVAL; datalines;
ALT 30
ALT 45
ALT 55
AST 25
AST 35
;
run;
proc means data=lb noprint nway;
  class LBTESTCD;
  var AVAL;
  output out=stats n=n mean=mean std=std min=min max=max;
run;
proc print data=stats; run;
