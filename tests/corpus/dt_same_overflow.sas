/* SAME-alignment day-overflow clamping for month/qtr/year intervals.
   Date variant clamps day-of-month to target month length (31JAN+1mo=29FEB,
   29FEB+1yr=28FEB). Datetime (DT*) SAME mirrors this, clamping the day while
   preserving time-of-day — qa-findings-tick148 BUG-intnxdtsameoverflow. */
data _null_;
  length a $10 b $10 c $10 d $10;
  a=put(intnx('month','31JAN2020'd,1,'s'),date9.);   /* 29FEB2020 */
  b=put(intnx('month','31MAR2020'd,1,'s'),date9.);   /* 30APR2020 */
  c=put(intnx('year','29FEB2020'd,1,'s'),date9.);    /* 28FEB2021 */
  d=put(intnx('qtr','31JAN2020'd,1,'s'),date9.);     /* 30APR2020 */
  put "month_jan31=" a;
  put "month_mar31=" b;
  put "year_feb29=" c;
  put "qtr_jan31=" d;
  /* datetime SAME preserves time-of-day in the no-overflow case */
  e=intnx('dtmonth','15MAR2020:14:32:00'dt,1,'s');
  put e=datetime.;
  /* DT day-overflow clamps to the target month's last day, time-of-day kept */
  f=intnx('dtmonth','31JAN2020:12:30:00'dt,1,'s');     /* 29FEB2020:12:30:00 */
  put f=datetime.;
  g=intnx('dtyear','29FEB2020:10:00:00'dt,1,'s');      /* 28FEB2021:10:00:00 */
  put g=datetime.;
  h=intnx('dtmonth','31MAR2020:12:00:00'dt,-1,'s');    /* 29FEB2020:12:00:00 */
  put h=datetime.;
  i=intnx('dtqtr','31JAN2020:06:00:00'dt,1,'s');       /* 30APR2020:06:00:00 */
  put i=datetime.;
  j=intnx('dtmonth2','31DEC2019:00:00:00'dt,1,'s');    /* 29FEB2020:00:00:00 */
  put j=datetime.;
  k=intnx('dtsemiyear','31AUG2019:23:59:59'dt,1,'s');  /* 29FEB2020:23:59:59 */
  put k=datetime.;
run;
