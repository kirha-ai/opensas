/* Macro that generates a PROC MEANS step for a chosen variable */
%macro summar(var);
  proc means data=lb n mean min max;
    var &var;
  run;
%mend;
data lb; input AVAL BVAL; datalines;
10 100
20 200
30 300
;
run;
%summar(AVAL)
