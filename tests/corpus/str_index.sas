data _null_;
  s = "hello world";
  p1 = index(s, "world");
  p2 = index(s, "xyz");
  put "p1=" p1 " p2=" p2;
run;
