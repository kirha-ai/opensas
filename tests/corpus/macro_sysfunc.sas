%let a = %sysfunc(upcase(hello));
%let b = %sysevalf(1.5 + 2.5);
%let c = %sysevalf(7 / 2);
%let d = %sysevalf(2.5 + 2.5, integer);

data _null_;
  put "a=&a b=&b c=&c d=&d";
run;
