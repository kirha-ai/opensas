data _null_;
  s = "abcabc";
  p1 = find(s, "bc");
  p2 = find(s, "bc", 3);
  put "p1=" p1 " p2=" p2;
run;
