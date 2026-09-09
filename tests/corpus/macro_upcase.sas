%let x = hello;
%let u = %upcase(&x);

data _null_;
  put "u=&u";
run;
