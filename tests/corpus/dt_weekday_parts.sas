data _null_;
  d = mdy(3,15,2020);
  wd=weekday(d); q=qtr(d); mo=month(d); yr=year(d); dd=day(d);
  put "date_parts=" wd q mo yr dd;
  dt = dhms(d, 14, 25, 9);
  hh=hour(dt); mi=minute(dt); ss=second(dt);
  put "time_parts=" hh mi ss;
run;
