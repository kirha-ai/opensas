/* BUG-fmtlabelwidth: an explicit WIDTH on a MATCHED user VALUE-format label was
   ignored — the label came back verbatim. SAS truncates the matched label to w
   (keeping the first w chars), left-justifies, and blank-pads a shorter label to
   w. With NO explicit width the label renders at the format's default width
   (the longest label's length). */
proc format;
  value f 1='LongLabel';   /* longest label 'LongLabel' => default width 9 */
run;
data _null_;
  x = 1;
  w4  = put(x, f4.);    /* explicit width 4 -> truncate to first 4 chars: 'Long' */
  w12 = put(x, f12.);   /* explicit width 12 -> blank-pad to 12 */
  wd  = put(x, f.);     /* no width -> full label (default width 9) */
  put "w4=[" w4 "]";
  put "w12=[" w12 "]";
  put "wd=[" wd "]";
run;
