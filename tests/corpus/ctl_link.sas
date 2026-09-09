data _null_;
  a = 5;
  link double;
  put "after link a=" a;
  return;
  double:
  a = a * 2;
  return;
run;
