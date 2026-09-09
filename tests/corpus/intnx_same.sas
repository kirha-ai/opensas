/* QA regression (BUG-intnxyearsame fixed): INTNX SAME alignment preserves
   month/day for year-length intervals (not day-of-year), clamps Feb29->Feb28. */
data _null_;
  a=intnx("year",mdy(6,15,2020),1,"same");
  b=intnx("year",mdy(6,15,2019),1,"same");
  c=intnx("semiyear",mdy(6,15,2020),2,"same");
  d=intnx("qtr",mdy(6,15,2020),4,"same");
  e=intnx("month",mdy(6,15,2020),12,"same");
  f=intnx("year",mdy(2,29,2020),1,"same");
  put "year2020=" a;
  put "year2019=" b;
  put "semiyear=" c;
  put "qtr=" d;
  put "month=" e;
  put "feb29clamp=" f;
run;
