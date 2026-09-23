/* BUG-8601packtime: the ISO 8601 BASIC packed time hhmmss<ffffff> reads as
   hh:mm:ss, not as a giant hour count (it used to land in parseTimeSecs'
   no-separator branch: 155300 x 3600 = 559080000). The informats' own doc
   examples, verbatim values (Informats Reference):
     B8601TM p.623  155300          -> 57180     (15:53:00)
     B8601DT p.619  20180915T155300 -> 1852645980 (2018-09-15 + 15:53:00)
   E8601TM reads the extended colon form (p.650) and stays lenient to the
   packed run; the colon/fraction forms are unchanged by the fix. TIMEw.
   (p.722) documents ONLY separator forms, so its packed read stays the
   whole-run-as-hours duration: 155300 hours = 559080000. */
data _null_;
  a = input("155300", b8601tm.);
  b = input("155300", e8601tm.);
  c = input("20180915T155300", b8601dt.);
  d = input("2018-09-15T155300", e8601dt19.);
  e = input("1553", b8601tm6.);        /* reduced run -> 15:53:00 */
  f = input("155300500000", b8601tm12.); /* packed fraction .5 */
  g = input("15:53:00", e8601tm.);
  h = input("15:53:00.5", e8601tm.);
  i = input("155300", time8.);         /* TIMEw.: hours, unchanged */
  j = input("15:53:00", time8.);
  put a b c d e f g h i j;
run;
/* The INPUT-statement path (readNumericStmt) reads the same packed run. */
data _null_;
  input t b8601tm.;
  put "STMT=" t;
  datalines;
155300
;
run;
