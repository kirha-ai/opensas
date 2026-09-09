data out(rename=(x=z));
  x = 5;
run;

data _null_;
  set out;
  put "z=" z;
run;
