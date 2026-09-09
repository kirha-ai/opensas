/* Descriptive stats per BY group (PROC MEANS BY) */
data lb; input PARAMCD $ AVAL; datalines;
ALT 30
ALT 45
ALT 55
AST 25
AST 35
;
run;
proc sort data=lb; by PARAMCD; run;
proc means data=lb n mean min max;
  by PARAMCD;
  var AVAL;
run;
