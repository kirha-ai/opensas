data _null_;
  array a{4} a1-a4 (5 10 15 20);
  s = sum(of a1-a4);
  keep a1 a2;
  drop a4;
  put "of_range_sum=" s " a1=" a1 " a2=" a2;
run;
