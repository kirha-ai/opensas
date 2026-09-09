data _null_;
  s = "alpha beta gamma";
  w1 = scan(s, 1);
  w2 = scan(s, 2);
  w3 = scan(s, -1);
  put "w1=" w1 " w2=" w2 " w3=" w3;
run;
