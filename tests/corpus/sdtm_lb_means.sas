/* LB: descriptive stats per lab test (PROC MEANS CLASS, display) */
data lb;
  input LBTESTCD $ LBSTRESN;
  datalines;
ALT 30
ALT 45
ALT 55
AST 25
AST 35
AST 40
;
run;

proc means data=lb n mean std min max;
  class LBTESTCD;
  var LBSTRESN;
run;
