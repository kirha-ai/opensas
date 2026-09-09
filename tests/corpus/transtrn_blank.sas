/* GH#60 ISS-transtrnblank: a quoted empty char literal ''/"" is a SINGLE BLANK,
   NEVER a zero-length string (SAS 9.4 Fns Ref, TRANSTRN p.1577). Only TRIMN('')
   is a genuine zero-length string. So transtrn(...,'') inserts a blank (target
   replaced), transtrn(...,trimn('')) removes the target, and lengthc('')=1. */
data _null_;
  r1 = transtrn('X-Y', '-', '');          /* '' = blank  -> "X Y" */
  r2 = transtrn('X-Y', '-', trimn(''));   /* zero-length -> "XY"  */
  l1 = lengthc(r1);
  l2 = lengthc(r2);
  le = lengthc('');                        /* single blank -> 1    */
  put "r1=[" r1 "] l1=" l1;
  put "r2=[" r2 "] l2=" l2;
  put "lengthc_empty=" le;
  if '' = ' ' then put "eq_blank=yes"; else put "eq_blank=no";
run;
