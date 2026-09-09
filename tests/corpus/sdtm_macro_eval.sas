/* Integer macro arithmetic with %EVAL driving a computed column */
%let n = %eval(3 + 4 * 2);
%let half = %eval(&n / 2);
data d;
  n = &n;
  half = &half;
run;
proc print data=d; run;
