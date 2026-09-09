%let s = abcdef;
%let sub = %substr(&s, 2, 3);

data _null_;
  put "sub=&sub";
run;
