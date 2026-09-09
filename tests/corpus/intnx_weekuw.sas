/* GAP-weekuw: WEEKU (U descriptor = WEEK, Sunday start) and WEEKW
   (Saturday-start week = WEEK offset by one day) intervals. */
data _null_;
  /* WEEKU behaves exactly like WEEK */
  u0 = intnx('weeku', '15jan2020'd, 0, 'b');      /* Sun 12JAN2020 */
  w0 = intnx('week',  '15jan2020'd, 0, 'b');      /* same */
  u1 = intnx('WEEKU', '15jan2020'd, 2, 'b');      /* +2 weeks */
  uc = intck('weeku', '12jan2020'd, '18jan2020'd);/* Sun->Sat same week = 0 */
  uc2 = intck('weeku', '12jan2020'd, '19jan2020'd);/* next Sunday = 1 */
  /* WEEKW starts Saturday */
  s0 = intnx('weekw', '15jan2020'd, 0, 'b');      /* Sat 11JAN2020 */
  sc = intck('weekw', '09jan2021'd, '10jan2021'd);/* Sat->Sun same week = 0 */
  sc2 = intck('weekw', '08jan2021'd, '09jan2021'd);/* Fri->Sat = 1 */
  se = intnx('weekw', '15jan2020'd, 0, 'e');      /* Fri 17JAN2020 */
  /* multiplier + shift-index come free via parseInterval */
  s2 = intnx('weekw2', '15jan2020'd, 1, 'b');
  us = intnx('weeku.4', '15jan2020'd, 0, 'b');    /* Wed-start week, like WEEK.4 */
  put u0= date9. w0= date9. u1= date9. uc= uc2= s0= date9. sc= sc2= se= date9.
      s2= date9. us= date9.;
run;

/* DT-prefixed variants route through the same buckets, at midnight */
data _null_;
  dt = '15jan2020:12:34:56'dt;
  du = intnx('dtweeku', dt, 0, 'b');  /* 12JAN2020:00:00:00 */
  dw = intnx('dtweekw', dt, 0, 'b');  /* 11JAN2020:00:00:00 */
  dc = intck('dtweekw', '09jan2021:08:00:00'dt, '10jan2021:09:00:00'dt); /* 0 */
  put du= datetime20. dw= datetime20. dc=;
run;
