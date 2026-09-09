data _null_;
  first = "Jane";
  last = "Doe";
  name = trim(first) || " " || last;
  put name;
run;
