data _null_;
  s = "cat dog cat";
  r = tranwrd(s, "cat", "fish");
  put "r=" r;
run;
