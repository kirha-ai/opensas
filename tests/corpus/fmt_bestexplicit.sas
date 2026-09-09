data _null_;
  a = put(1/3, best12.);
  b = put(1e20, best12.);
  c = put(42, best8.);
  put "a=[" a "]";
  put "b=[" b "]";
  put "c=[" c "]";
run;
