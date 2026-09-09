data _null_;
  array a{3} a1-a3 (5 10 15);
  do over a;
    a = a + 1;
  end;
  put "a1=" a1 " a2=" a2 " a3=" a3;
run;
