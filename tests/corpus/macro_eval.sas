%let a = 3;
%let b = 4;
%let n = %eval(&a + &b);
%let m = %eval(&a * &b);
data _null_;
  put "n=&n m=&m";
run;

%macro check(x);
  %if %eval(&x > 2) %then %let r = big;
  %else %let r = small;
  data _null_;
    put "x=&x r=&r";
  run;
%mend;
%check(5)
%check(1)
