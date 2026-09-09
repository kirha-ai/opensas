/* GAP-fmtwrite-unimpl: Dw.p (SAS 9.4 Formats Reference p.170 — default w 12,
   p default 3, p=0 -> 3). All six documented d10.4 rows: m >= p -> 1 decimal,
   m < p -> 5, right-justified in 10. */
data _null_;
  input x;
  put x d10.4;
  datalines;
12345
1234.5
123.45
12.345
1.2345
.12345
;
run;
data _null_;
  a = 1.2345; put a d.;      /* default w 12, p 3 */
  b = 12345;  put b d10.0;   /* p=0 -> 3 */
  c = .;      put c d10.4;
run;
