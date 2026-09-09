/* GAP-pictureround: PICTURE (round) option rounds the scaled value to the last
   digit selector instead of the SAS-default truncation (BUG-picturetrunc).
   3.98 under '009.9' → scaled 39.8 → truncated `  3.9` by default, rounded
   `  4.0` with (round). Combines with MULT=: 12.999×100 = 1299.9 → 1300. */
proc format;
  picture pt low-high='009.9';
  picture pr low-high='009.9' (round);
  picture pm low-high='00009' (mult=100 round);
run;
data _null_;
  x = 3.98;
  put x pt.;   /* trunc → `  3.9` */
  put x pr.;   /* round → `  4.0` */
  y = 12.999;
  put y pm.;   /* round × mult → ` 1300` */
run;
