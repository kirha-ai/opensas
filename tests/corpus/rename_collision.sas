data d;
  input a b;
  datalines;
1 2
;
run;
data _null_;
  set d(rename=(a=b));
  put "a=" a " b=" b;
run;
