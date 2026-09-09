data _null_;
  first = "John";
  mi = " ";
  last = "Smith";
  full = catx(" ", first, mi, last);
  tag = catx("-", "A", "", "B", "C");
  put "full=" full;
  put "tag=" tag;
run;
