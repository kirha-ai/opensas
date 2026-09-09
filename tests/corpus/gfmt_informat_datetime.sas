/* datetime_informat: DATETIME / E8601DT / TIME / HHMMSS read via input(). Phase-G. */
data _null_;
  f = input("04JUL2020:13:30:45", datetime19.);  put "DATETIME=" f;
  g = input("2020-07-04T13:30:45", e8601dt.);     put "E8601DT="  g;
  h = input("13:30:45", time8.);                  put "TIME="     h;
  i = input("13:30:45", hhmmss8.);                put "HHMMSS="   i;
run;
