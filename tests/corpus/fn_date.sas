data _null_;
  d = mdy(3, 15, 2020);
  y = year(d);
  m = month(d);
  dd = day(d);
  wd = weekday(d);
  put "d=" d " y=" y " m=" m " dd=" dd " wd=" wd;
  put "fmt=" d date9.;
run;
