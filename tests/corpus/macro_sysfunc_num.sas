%let a = %sysfunc(max(3,7));
%let b = %sysfunc(int(4.9));
%let c = %sysfunc(abs(-5));
%let d = %sysfunc(round(3.14159, 0.01));
%let e = %sysfunc(upcase(hi));
data _null_;
  put "a=&a b=&b c=&c d=&d e=&e";
run;
