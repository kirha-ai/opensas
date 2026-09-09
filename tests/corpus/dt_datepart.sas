data _null_;
  dt = dhms(mdy(6,1,2021), 13, 30, 45);
  d = datepart(dt);
  t = timepart(dt);
  length ds $10 ts $10;
  ds = put(d, date9.);
  ts = put(t, time8.);
  put "datepart=" ds " timepart=" ts;
run;
