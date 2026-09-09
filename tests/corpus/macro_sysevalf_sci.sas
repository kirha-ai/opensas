/* %sysevalf handles floating-point scientific notation (e/E with optional sign),
   not just plain decimals — regression guard for BUG-sysevalfsci. */
%let a = %sysevalf(1e10);
%let b = %sysevalf(2 + 1e3);
%let c = %sysevalf(1.5e3);
%let d = %sysevalf(1E3);
%let e = %sysevalf(1e-2);
%let f = %sysevalf(2.5e2 + 1);
data _null_;
  put "a=&a b=&b c=&c d=&d e=&e f=&f";
run;
