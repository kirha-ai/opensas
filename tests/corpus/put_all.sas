data _null_;
  length name $ 5 city $ 8;
  name = "Bob";
  city = "Rome";
  age = 42;
  put _all_;
  put _character_;
run;
