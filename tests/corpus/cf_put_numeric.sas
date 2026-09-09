data _null_;
  length s $10;
  s = put(0.456, percent8.1); put "pct=" s;
  s = put(1234.5678, 8.2); put "fixed=" s;
  s = put(-42.567, 8.1); put "neg=" s;
  s = put(0.5, percent6.); put "pct0=" s;
  s = put(3, z3.); put "zero3=" s;
run;
