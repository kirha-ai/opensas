data _null_;
  length a b $5;
  a = ""; b = "hi";
  s = coalescec(a, b, "NA");
  a2 = ""; b2 = "";
  s2 = coalescec(a2, b2, "NA");
  put "s=" s " s2=" s2;
run;
