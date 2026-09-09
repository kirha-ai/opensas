data _null_;
  t = hms(13, 45, 30);
  h = hour(t);
  m = minute(t);
  s = second(t);
  put "t=" t;
  put "h=" h " m=" m " s=" s;
run;
