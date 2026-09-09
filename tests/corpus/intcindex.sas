/* INTCINDEX: cycle index of a date — week-of-year for day/week, month/qtr of year.
   Doc: intcindex('day','01SEP2021'd)=36. Phase-F. */
data _null_;
  a = intcindex('day',   '01SEP2021'd);
  b = intcindex('week',  '01SEP2021'd);
  c = intcindex('month', '15MAR2021'd);
  d = intcindex('qtr',   '15AUG2021'd);
  e = intcindex('day',   '04APR2021'd);
  put "day=" a;
  put "week=" b;
  put "month=" c;
  put "qtr=" d;
  put "day2=" e;
run;
