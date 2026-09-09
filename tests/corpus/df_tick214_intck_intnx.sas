/* doc-finder tick214: INTCK/INTNX interval audit — verified-correct values only.
   Boundary counting, multipliers, shift-index, alignment, DT/time, WEEKDAY,
   ISO WEEKV. Each value hand-checked against SAS 9.4 documented behavior.
   (DT-month-family CONTINUOUS and invalid-alignment cases are NOT here —
   they are open findings in docs/findings/doc-finder-tick214.md.) */
data _null_;
  /* INTCK boundary crossings */
  c1 = intck('year', '31dec2020'd, '01jan2021'd);   /* 1 boundary, not 0 */
  c2 = intck('year', '01jan2020'd, '31dec2020'd);   /* 0 */
  c3 = intck('month', '31jan2021'd, '01feb2021'd);  /* 1 */
  c4 = intck('week', '09jan2021'd, '10jan2021'd);   /* Sat->Sun: 1 */
  c5 = intck('qtr', '31mar2020'd, '01apr2020'd);    /* 1 */
  /* multiplier + shift-index */
  m1 = intck('month2', '01jan2020'd, '01may2020'd); /* 2 */
  m2 = intck('qtr.2', '01jan2020'd, '15feb2020'd);  /* Feb 1 boundary: 1 */
  m3 = intck('qtr.2', '15feb2020'd, '15mar2020'd);  /* none: 0 */
  m4 = intck('week.2', '03jan2021'd, '04jan2021'd); /* Mon-start wk: 1 */
  m5 = intck('year.10', '15jun2020'd, '15oct2020'd);/* fiscal Oct 1: 1 */
  /* CONTINUOUS (date scale) */
  k1 = intck('month', '14feb2021'd, '14mar2021'd, 'c'); /* exactly 1 */
  k2 = intck('month', '14feb2021'd, '13mar2021'd, 'c'); /* 0 */
  k3 = intck('month', '14feb2021'd, '15jan2021'd, 'c'); /* backward: 0 */
  k4 = intck('year', '01mar2020'd, '01mar2021'd, 'c');  /* 1 */
  k5 = intck('week', '15jan2020'd, '29jan2020'd, 'c');  /* 2 */
  put c1= c2= c3= c4= c5= m1= m2= m3= m4= m5= k1= k2= k3= k4= k5=;
run;

data _null_;
  format n1-n10 date9.;
  /* INTNX alignments */
  n1 = intnx('month', '15jan2020'd, 1, 'b');   /* 01FEB2020 */
  n2 = intnx('month', '15jan2020'd, 1, 'e');   /* 29FEB2020 */
  n3 = intnx('month', '15jan2020'd, 1, 'm');   /* 15FEB2020 */
  n4 = intnx('month', '15jan2020'd, 1, 's');   /* 15FEB2020 */
  n5 = intnx('month', '31jan2020'd, 1, 's');   /* clamp 29FEB2020 */
  n6 = intnx('week', '15jan2020'd, 1, 'b');    /* Sun 19JAN2020 */
  n7 = intnx('week', '15jan2020'd, 1, 'm');    /* Wed 22JAN2020 */
  n8 = intnx('semimonth', '05mar2020'd, 1, 'e'); /* 31MAR2020 */
  n9 = intnx('tenday', '05mar2020'd, 3, 'b');    /* 01APR2020 */
  n10 = intnx('weekday', '13mar2020'd, 1, 'b');  /* Mon 16MAR2020 */
  /* negative n / n=0 / fractional n (trunc toward zero) */
  x1 = intnx('month', '15jan2020'd, -1, 'b');  /* 01DEC2019 */
  x2 = intnx('month', '15jan2020'd, -0.5);     /* 01JAN2020 */
  put n1= n2= n3= n4= n5= n6= n7= n8= n9= n10=;
  put x1= date9. x2= date9.;
run;

data _null_;
  /* datetime / time intervals */
  d1 = intnx('dtmonth', '15jan2020:10:30:00'dt, 1, 'e'); /* 29FEB2020:23:59:59 */
  d2 = intnx('dtmonth', '31jan2020:12:30:00'dt, 1, 's'); /* 29FEB2020:12:30:00 */
  d3 = intnx('dtyear', '29feb2020:08:00:00'dt, 1, 's');  /* 28FEB2021:08:00:00 */
  d4 = intnx('dtweek', '15jan2020:10:30:00'dt, 1, 's');  /* 22JAN2020:10:30:00 */
  h1 = intck('hour', '10:59:00't, '11:01:00't);    /* 1 */
  h2 = intck('dtday', '15jan2020:23:00:00'dt, '16jan2020:01:00:00'dt); /* 1 */
  h3 = intck('minute30', '10:15:00't, '11:00:00't); /* 2 */
  h4 = intck('dtmonth', '15jan2020:10:30:00'dt, '15feb2020:09:00:00'dt); /* 1 */
  put d1= datetime19. d2= datetime19. d3= datetime19. d4= datetime19.;
  put h1= h2= h3= h4=;
run;

data _null_;
  format w1-w3 date9.;
  /* ISO 8601 WEEKV: Monday-start, week 1 contains Jan 4 */
  w1 = intnx('weekv', '01jan2020'd, 0, 'b');  /* Mon 30DEC2019 */
  w2 = intnx('weekv', '01jan2020'd, 0, 'e');  /* Sun 05JAN2020 */
  w3 = intnx('weekv', '15jan2020'd, 4, 'b');  /* Mon 10FEB2020 */
  v1 = intck('weekv', '01jan2020'd, '06jan2020'd);  /* 1 */
  v2 = intck('weekday', '13mar2020'd, '16mar2020'd);/* Fri->Mon: 1 */
  v3 = intck('weekday', '13mar2020'd, '14mar2020'd);/* Fri->Sat: 0 */
  put w1= w2= w3=;
  put v1= v2= v3=;
run;
