data _null_;
  x = "a1b2c3";
  d = compress(x, , "kd");
  y = compress("  keep  spaces  ");
  put "d=" d;
  put "y=" y;
run;
