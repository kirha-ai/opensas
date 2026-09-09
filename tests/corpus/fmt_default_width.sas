/* GH#63 ISS-fmtdefwidth: PUT of a value matching NO range of a user-defined
   CHAR format (no OTHER=) returns the source value TRUNCATED to the format's
   width. With no explicit width the width DEFAULTS to the longest label's
   length. opensas truncated with an explicit width but ignored the default. */
proc format;
  value $wf 'a'='SHORT';                              /* longest label 'SHORT' => default width 5 */
  value $mf 'x'='Male' 'y'='Female' other='Unknown';  /* has OTHER= */
run;
data _null_;
  length x $30;
  x = 'UNMATCHEDLONGVALUE';
  r5 = put(x, $wf5.);   /* explicit width 5 */
  rd = put(x, $wf.);    /* default width (should be 5) */
  l5 = length(r5); ld = length(rd);
  put "explicit=[" r5 "] len=" l5;   /* regression: explicit width already worked */
  put "default=[" rd "] len=" ld;    /* the fix: default width truncates too */
  m = put('a', $wf.);                /* matched value still returns its label */
  put "matched=[" m "]";
  o = put('zzz', $mf.);              /* no match -> OTHER= still wins */
  put "other=[" o "]";
  q = put(x, $10.);                  /* plain built-in $w. -> truncate to w (unchanged) */
  put "plain_w10=[" q "]";
  z = put('hi', $20.);              /* plain built-in $w. -> blank-pad to w (NOT label width) */
  put "plain_w20=[" z "]";
run;
