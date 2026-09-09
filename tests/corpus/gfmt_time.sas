/* time_format: TIME / TIMEAMPM / TOD / DATETIME write formats. Phase-G. */
data _null_;
  d = mdy(7,4,2020); t = hms(13,30,45); dt = dhms(d,13,30,45);
  put "TIME="     t time8.;
  put "TIMEAMPM=" t timeampm11.;
  put "TOD="      t tod8.;
  put "DATETIME=" dt datetime19.;
run;
