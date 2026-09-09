/* Floating-point macro arithmetic with %SYSEVALF (vs integer %EVAL) */
%let ratio = %sysevalf(3 / 4);
%let prod  = %sysevalf(1.5 * 2.5);
data d;
  ratio = &ratio;
  prod  = &prod;
run;
proc print data=d; run;
