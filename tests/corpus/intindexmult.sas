/* BUG-intindexmult: INTINDEX/INTCINDEX fold the interval multiplier into the
   multi-unit period (index cycles 1..INTSEAS). SAS 9.4 values:
   a,b per doc-finder tick180 (labeled SAS 2); e,f,g per the INTINDEX doc
   example (01APR2020: MONTH2→2, MONTH6→1, QTR2→1). h..k are the same
   documented fold (SEMIMONTH2 = monthly periods → 3; MONTH3 May → Apr-Jun
   bucket 2). Non-multiplied cases (c,d,cc,cd,cg) unchanged. l,cf are NOT
   SAS-verified — week-cycle multipliers return honest missing by design. */
data _null_;
  a  = intindex('month2',  '15MAR2020'd);  put "a=" a;   /* SAS 2 */
  b  = intindex('qtr2',    '15AUG2020'd);  put "b=" b;   /* SAS 2 */
  c  = intindex('month',   '15MAR2020'd);  put "c=" c;   /* SAS 3 */
  d  = intindex('qtr',     '15AUG2020'd);  put "d=" d;   /* SAS 3 */
  e  = intindex('month2',  '01APR2020'd);  put "e=" e;   /* SAS 2 */
  f  = intindex('month6',  '01APR2020'd);  put "f=" f;   /* SAS 1 */
  g  = intindex('qtr2',    '01APR2020'd);  put "g=" g;   /* SAS 1 */
  h  = intindex('semiyear2',  '15AUG2020'd); put "h=" h; /* 1 */
  i  = intindex('semimonth2', '20MAR2013'd); put "i=" i; /* 3 */
  j  = intindex('month3',  '15MAY2020'd);  put "j=" j;   /* 2 */
  k  = intindex('tenday2', '15FEB2013'd);  put "k=" k;   /* 3 */
  l  = intindex('day2',    '15MAR2020'd);  put "l=" l;   /* missing (not SAS-verified) */
  ca = intcindex('month2', '15MAR2020'd);  put "ca=" ca; /* 2 (6-season cycle) */
  cb = intcindex('qtr2',   '15AUG2020'd);  put "cb=" cb; /* 2 */
  cc = intcindex('month',  '15MAR2020'd);  put "cc=" cc; /* 3 */
  cd = intcindex('qtr',    '15AUG2020'd);  put "cd=" cd; /* 3 */
  ce = intcindex('semiyear2', '15AUG2020'd); put "ce=" ce; /* 1 */
  cf = intcindex('week2',  '01SEP2021'd);  put "cf=" cf; /* missing (not SAS-verified) */
  cg = intcindex('day',    '01SEP2021'd);  put "cg=" cg; /* 36 */
run;
