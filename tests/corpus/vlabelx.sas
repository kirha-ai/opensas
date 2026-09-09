data _null_;
  length name $ 8;
  name = "Bob";
  age = 42;
  ln = vlabelx("name");
  la = vlabelx("age");
  put "VLABELX_name=" ln;
  put "VLABELX_age=" la;
run;
