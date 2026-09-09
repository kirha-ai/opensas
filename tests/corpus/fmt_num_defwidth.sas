/* NOTE-numfmtdefwidth: an UNMATCHED numeric user VALUE format value with no
   explicit width and no OTHER= ignored the format's default width — the raw
   value came back with no padding. SAS right-justifies the raw value in the
   format's default width (the longest label's length). Numeric twin of the
   CHAR fix (tick78). Matched labels and an explicit width already worked. */
proc format;
  value g 1='one' 2='two';   /* longest label => default width 3 */
run;
data _null_;
  hit  = put(1, g.);   /* matched -> label 'one'                        */
  miss = put(9, g.);   /* unmatched, no width -> raw 9 in default width  */
  ex   = put(9, g5.);  /* explicit width 5 -> raw 9 right-justified in 5 */
  put "hit=[" hit "]";
  put "miss=[" miss "]";
  put "ex=[" ex "]";
run;
