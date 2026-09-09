/* BUG-fmtextrememag: accurate pow10f so wide BEST/COMMA of extreme magnitudes
   don't drift to 9.999...E<n> (was pow10f ULP drift at |e|>22).
   BUG-datefmtedge: date formats render the year-1 / year-9999 edges instead of
   falling back to the raw SAS day number (widened clamp to mdy(1,1,1)..mdy(12,31,9999)). */
data _null_;
  put 1e300 best32.;   /* 1E300 */
  put 5e-200 best30.;  /* 5E-200 */
  put 1e300 comma32.;  /* 1E300 */
  d1=mdy(1,1,1);        put d1 date9.;  /* 01JAN0001 */
  d2=mdy(12,31,9999);   put d2 date9.;  /* 31DEC9999 */
  /* regression: default BEST12. and normal magnitudes unaffected */
  t=1/3;               put t best12.;   /* 0.3333333333 */
  put 1e13 best12.;                     /* 1E13 */
run;
