data src;
  input a b;
  datalines;
1 2
;
run;

data out(rename=(a=b));
  set src;
run;

data _null_;
  set out;
  c = b + 1;
  put "a=" a " b=" b " c=" c;
run;
