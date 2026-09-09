/* GAP-intnxintervals: INTNX/INTCK route through parseInterval — WEEKDAY,
   SEMIYEAR/SEMIMONTH/TENDAY in INTCK, DT/time intervals, multipliers (MONTH2),
   and shift-index (QTR.2, YEAR.3, MONTH2.2) all recognised. */
data _null_;
  /* F1: WEEKDAY in INTNX and INTCK */
  a  = intnx('weekday', '01jan2020'd, 3);            /* Wed +3 -> Mon 06JAN2020 */
  a2 = intnx('weekday', '15mar2020'd, 3);            /* Sun +3 -> Wed 18MAR2020 */
  a3 = intck('weekday', '13mar2020'd, '18mar2020'd); /* Fri->Mon->Tue->Wed = 3 */
  /* F2: INTCK parity for SEMIYEAR / SEMIMONTH / TENDAY */
  b1 = intck('semiyear', '01jan2020'd, '01jul2020'd);
  b2 = intck('semimonth', '01mar2020'd, '20mar2020'd);
  b3 = intck('tenday', '01mar2020'd, '25mar2020'd);
  /* F4: multiplier MONTH2 */
  m  = intnx('month2', '15mar2020'd, 1);             /* next 2-month period */
  mc = intck('month2', '01jan2020'd, '01may2020'd);
  me = intnx('month2', '15mar2020'd, 0, 'e');        /* END of the Mar-Apr period */
  /* F5: shift-index */
  q  = intnx('qtr.2', '15jan2020'd, 0, 'b');         /* shifted quarter Nov-Jan */
  y  = intnx('year.3', '15jan2020'd, 0, 'b');        /* year starting 01Mar */
  m2 = intnx('month2.2', '15jan2020'd, 0, 'b');      /* bimonthly, even months */
  put a= date9. a2= date9. a3= b1= b2= b3= m= date9. mc= me= date9.
      q= date9. y= date9. m2= date9.;
run;

/* F3: datetime (DT-prefixed) and time intervals on datetime values */
data _null_;
  dt = '15mar2020:12:00:00'dt;
  dm = intnx('dtmonth', dt, 1);        /* -> 01APR2020:00:00:00 */
  dd = intnx('dtday', dt, 1, 's');     /* SAME -> 16MAR2020:12:00:00 */
  hh = intnx('hour', '01jan2020:12:00:00'dt, 5); /* -> 01JAN2020:17:00:00 */
  ck = intck('dtmonth', '01jan2020:00:00:00'dt, '01mar2020:00:00:00'dt);
  ch = intck('hour', '01jan2020:00:00:00'dt, '01jan2020:12:00:00'dt);
  put dm= datetime19. dd= datetime19. hh= datetime19. ck= ch=;
run;
