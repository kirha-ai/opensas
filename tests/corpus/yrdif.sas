data _null_;
  a = yrdif(mdy(1,1,2020), mdy(1,1,2021), 'ACT/ACT');
  b = yrdif(mdy(1,1,2021), mdy(1,1,2022), 'ACT/365');
  c = yrdif(mdy(1,1,2020), mdy(7,1,2020), '30/360');
  put "a=" a;
  put "b=" b;
  put "c=" c;
run;
