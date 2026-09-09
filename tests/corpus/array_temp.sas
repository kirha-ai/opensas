data _null_;
  array t{3} _temporary_ (10 20 30);
  total = t{1} + t{2} + t{3};
  put "total=" total;
run;
