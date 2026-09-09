/* BUG-charwleadblank: the INPUT statement must choose leading-blank treatment
   by informat (Language Reference: Concepts p.510/517) — $CHARw. KEEPS leading blanks, plain $w.
   STRIPS them (left-aligns) — on both the column-pointer (@n) read and the
   non-pointer formatted read. Mirror of the INPUT() function path.
   Dataline is "  XY ZZZ" (two leading blanks, significant). */
data _null_;
  /* column-pointer branch: both vars read cols 1-5 = "  XY " */
  input @1 a $char5. @1 b $5.;
  put "[" a "]" / "[" b "]";
  datalines;
  XY ZZZ
;
run;
/* expected a ($char5., kept): "  XY" ; b ($5., left-aligned): "XY" */

data _null_;
  /* non-pointer formatted branch: c reads cols 1-4 = "  XY", d cols 5-8 = " ZZZ" */
  input c $char4. d $4.;
  put "[" c "]" / "[" d "]";
  datalines;
  XY ZZZ
;
run;
/* expected c ($char4., kept): "  XY" ; d ($4., left-aligned): "ZZZ" */
