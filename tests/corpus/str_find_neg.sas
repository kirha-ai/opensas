data _null_;
  s = "abcabc";
  p1 = find(s, "bc", -6);
  p2 = find(s, "bc", -4);
  p3 = find(s, "abc", -10);
  p4 = find(s, "zz", -6);
  put "p1=" p1 " p2=" p2 " p3=" p3 " p4=" p4;
run;
