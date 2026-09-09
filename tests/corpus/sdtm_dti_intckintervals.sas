/* INTCK boundary counts across several interval units */
data d;
  from = "01JAN2024"d;
  to   = "15OCT2024"d;
  nday   = intck("day", from, to);
  nweek  = intck("week", from, to);
  nmonth = intck("month", from, to);
  nqtr   = intck("qtr", from, to);
  nyear  = intck("year", "31DEC2023"d, "01JAN2024"d);
run;
proc print data=d; var nday nweek nmonth nqtr nyear; run;
