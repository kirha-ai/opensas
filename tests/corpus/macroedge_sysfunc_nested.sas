/* Nested %sysfunc calls and multi-arg data-step functions inside the macro processor. corpus-macroedge. */
%let a = %sysfunc(strip(%sysfunc(repeat(x, 2))));
%let b = %sysfunc(catx(-, DM, AE, LB));
%let c = %sysfunc(coalescec(, , third));
%let n = %sysfunc(length(%sysfunc(compress(a b c))));
data _null_;
  put "a=&a b=&b c=&c n=&n";
run;
