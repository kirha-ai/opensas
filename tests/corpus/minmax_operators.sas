/* GAP-minmaxop: the `><` (MIN) and `<>` (MAX) operators, plus the MIN/MAX infix
   word forms. Group I precedence — binds tighter than * / , looser than ** ;
   a missing value ranks lowest (unlike the min()/max() functions). */
data _null_;
  sa = 5 >< 3;  sb = 5 <> 3;
  wa = 5 min 3; wb = 5 max 3;
  pa = 2 * 3 >< 4;  pb = 10 >< 2 ** 3;
  ch = 9 >< 4 >< 7;
  m = . >< 5;  n = . <> 5;
  put "SYM sa=" sa " sb=" sb;
  put "WORD wa=" wa " wb=" wb;
  put "PREC pa=" pa " pb=" pb;
  put "CHAIN ch=" ch;
  put "MISS m=" m " n=" n;
run;
