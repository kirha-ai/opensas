/* BUG-intckdtcontinuous: DT-prefixed month-family INTCK CONTINUOUS counts
   anniversaries on the seconds scale (day + time-of-day), not the discrete
   boundary count; and an unknown non-blank INTNX alignment / INTCK method is
   missing + NOTE (blank still defaults BEGINNING / DISCRETE). */
data _null_;
  /* DTMONTH continuous — anniversary carries the time-of-day */
  s1 = intck('dtmonth','15jan2020:10:00:00'dt,'15mar2020:09:00:00'dt,'c'); /* 1: 15MAR 10:00 anniv not reached */
  s2 = intck('dtmonth','15jan2020:10:00:00'dt,'15mar2020:11:00:00'dt,'c'); /* 2: anniv passed */
  s3 = intck('dtmonth','15jan2020:10:30:00'dt,'15feb2020:09:00:00'dt,'c'); /* 0 */
  s4 = intck('dtmonth','15jan2020:10:30:00'dt,'15feb2020:10:30:00'dt,'c'); /* 1: exact anniv */
  /* DTYEAR continuous */
  y1 = intck('dtyear','15jan2019:10:00:00'dt,'14jan2020:10:00:00'dt,'c');  /* 0 */
  y2 = intck('dtyear','15jan2019:10:00:00'dt,'15jan2020:10:00:00'dt,'c');  /* 1 */
  /* DTQTR / DTSEMIYEAR continuous */
  q1 = intck('dtqtr','15jan2020:10:00:00'dt,'15apr2020:09:00:00'dt,'c');   /* 0 */
  q2 = intck('dtqtr','15jan2020:10:00:00'dt,'15apr2020:11:00:00'dt,'c');   /* 1 */
  h1 = intck('dtsemiyear','15jan2020:10:00:00'dt,'14jul2020:20:00:00'dt,'c'); /* 0 */
  h2 = intck('dtsemiyear','15jan2020:10:00:00'dt,'16jul2020:09:00:00'dt,'c'); /* 1 */
  /* backward direction */
  b1 = intck('dtmonth','15mar2020:09:00:00'dt,'15jan2020:10:00:00'dt,'c'); /* -1 */
  b2 = intck('dtyear','14jan2020:10:00:00'dt,'15jan2019:10:00:00'dt,'c');  /* 0 */
  put s1= s2= s3= s4= y1= y2= q1= q2= h1= h2= b1= b2=;
run;

data _null_;
  /* invalid non-blank alignment/method → missing + NOTE */
  j1 = intnx('month','15jan2020'd,1,'X');
  j2 = intck('month','15jan2020'd,'15feb2020'd,'bogus');
  /* blank/missing/empty keeps the defaults: BEGINNING / DISCRETE */
  j3 = intnx('month','15jan2020'd,1,' ');   /* 01FEB2020 */
  j4 = intck('month','15jan2020'd,'15feb2020'd,'');  /* 1 */
  j5 = intnx('month','15jan2020'd,1);       /* 01FEB2020 */
  put j1= j2= j4=;
  put j3= date9. j5= date9.;
run;
