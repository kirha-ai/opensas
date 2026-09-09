data _null_;
  x = 255;
  put x hex8.;
  d = md5("abc");
  put d $hex32.;
run;
