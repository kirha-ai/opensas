data _null_;
  s = "abcde";
  a = substr(s, 2);
  b = substr(s, 2, 2);
  c = substr(s, 6);
  d = substr(s, 3, 100);
  e = substr(s, 0);
  put "a=" a " b=" b " c=[" c "] d=" d " e=" e;
run;
