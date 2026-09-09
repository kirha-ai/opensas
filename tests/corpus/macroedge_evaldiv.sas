/* %eval integer truncation (incl. negatives, toward zero) vs %sysevalf real division. corpus-macroedge. */
%let a = %eval(7/2);
%let b = %eval(-7/2);
%let c = %eval(9/4);
%let d = %sysevalf(7/2);
data _null_;
  put "a=&a b=&b c=&c d=&d";
run;
