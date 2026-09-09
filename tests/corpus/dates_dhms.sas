data _null_;
  dt = dhms(21915, 1, 1, 1);
  d = datepart(dt);
  tm = timepart(dt);
  put "dt=" dt;
  put "d=" d " tm=" tm;
run;
