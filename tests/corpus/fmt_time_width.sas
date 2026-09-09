/* BUG-fmttimewidth: TIME/TOD/DATETIME honor width w (hh vs hh:mm vs hh:mm:ss)
   and decimals d (fractional seconds) — SAS 9.4 Formats reference. */
data _null_;
  t  = '14:45:32't;
  dt = '17MAR2013:14:45:32'dt;
  put t time5.;      /* hh:mm — seconds dropped */
  put t time8.;      /* hh:mm:ss */
  put t time11.2;    /* d=2 fractional seconds */
  put t tod12.3;     /* d=3 */
  put dt datetime13.; /* date + hh:mm, no seconds */
  put dt datetime18.; /* wide default form, unchanged */
  put t time2.;      /* hh only */
  t2 = t + 0.25;
  put t2 time11.2;   /* a real fraction renders, not just zeros */
run;
