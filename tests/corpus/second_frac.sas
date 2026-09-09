data _null_;
  s = second(hms(10,30,15.75));
  s2 = second('14:30:45.5't);
  tp = timepart('01JAN2020:10:30:45.9'dt);
  put "s=" s " s2=" s2;
  put "tp=" tp time12.3;
  /* integer controls: must stay whole */
  h = hour(hms(10,30,15.75));
  m = minute(hms(10,30,15.75));
  dp = datepart('01JAN2020:10:30:45.9'dt);
  dy = day(dp);
  mo = month(dp);
  yr = year(dp);
  put "h=" h " m=" m " dp=" dp " dy=" dy " mo=" mo " yr=" yr;
run;
