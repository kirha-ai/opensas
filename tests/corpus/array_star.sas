data _null_;
  array a{*} a1-a4 (2 4 6 8);
  s = sum(of a{*});
  m = max(of a{*});
  put "s=" s " m=" m;
run;
