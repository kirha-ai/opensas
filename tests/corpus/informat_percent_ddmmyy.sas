/* BUG-percentinformat2 + BUG-ddmmyyfnpacked:
   PERCENTw.d reads parens as negative; packed DDMMYY6./MMDDYY6. parse on the
   INPUT() function path. */
data _null_;
  input p percent8.;
  put p=;
  datalines;
(25%)
25%
25
;
run;
data _null_;
  p1 = input("(25%)", percent8.);  /* parens = negative → -0.25 */
  p2 = input("25%", percent8.);    /* strips %, /100 → 0.25 */
  put p1= p2=;
  d = input("150312", ddmmyy6.);   /* packed → 15MAR2012 = SAS day 19067
                                      (date(2012,3,15) - date(1960,1,1)) */
  m = input("031512", mmddyy6.);   /* packed MMDDYY → same day */
  dd = put(d, date9.);
  put d= m= dd=;
run;
