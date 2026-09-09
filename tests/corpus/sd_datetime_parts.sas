data _null_;
  dt = dhms(mdy(3,15,2020), 9, 45, 30);
  d = datepart(dt);
  hh = hour(dt); mi = minute(dt); ss = second(dt);
  wd = weekday(d); q = qtr(d); mo = month(d);
  put "hms_parts=" hh mi ss;
  put "date_parts=" wd q mo;
run;
