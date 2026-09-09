data _null_;
  length a b c $ 3;
  a = "hello";
  b = "world";
  c = "abcde";
  put "a=" a " b=" b " c=" c;
run;
