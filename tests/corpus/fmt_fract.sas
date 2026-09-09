/* GAP-fmtwrite-unimpl: FRACTw. (SAS 9.4 Formats Reference p.224 — default w 10,
   range 4–32, reduced fractions, right-justified). The two documented rows are
   0.6666666667 fract8. -> `     2/3` and 0.2784 fract8. -> ` 174/625`. */
data _null_;
  a = 0.6666666667; put a fract8.;
  b = 0.2784;       put b fract8.;
  c = 0.6666666667; put c fract.;
  d = -0.5;         put d fract8.;
  e = 5;            put e fract8.;
  f = .;            put f fract8.;
  g = 123456;       put g fract7.;  /* n/1 overflows 7 -> the exact integer */
  h = 123456;       put h fract8.;  /* fits -> 123456/1 */
run;
