/* GAP-fmtdefwidth-num: a named numeric format with NO explicit width renders at
   its documented SAS DEFAULT width (COMMA/COMMAX/DOLLAR/DOLLARX/NEGPAREN/PERCENT
   = 6, SAS 9.4 Formats Reference), right-justified into it — the width-less
   forms used to print at natural width with no padding. Explicit-width uses are
   byte-identical controls. */
data _null_;
  p = 0.5;   put "pct_def=["  p percent.   "]";  /* SAS:    50% */
  n = 1235;  put "comma_def=[" n comma.     "]";  /* SAS:   1,235 */
  d = 100;   put "dollar_def=[" d dollar.   "]";  /* SAS:    $100 */
  np = -12;  put "negp_def=["  np negparen. "]";  /* SAS:    (12) */
  cx = 1235; put "commax_def=[" cx commax.  "]";  /* SAS:   1.235 */
  /* explicit-width controls: unchanged */
  p2 = 0.075; put "pct8=["  p2 percent8.1 "]";   /*     7.5% */
  n2 = 1234.5; put "comma10=[" n2 comma10.2 "]"; /*  1,234.50 */
  d2 = 12345.678; put "dollar12=[" d2 dollar12.2 "]"; /*  $12,345.68 */
run;
