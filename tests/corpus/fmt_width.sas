/* QA regression (BUG-fmtwidth fixed): numeric formats fit within width w on
   overflow (reduce decimals, drop separators, BEST/E-notation). */
data _null_;
  a=put(1234.567, 6.2); la=length(a);
  b=put(1.23456, 4.3);  lb=length(b);
  c=put(1234567, comma6.); lc=length(c);
  d=put(1000000, dollar8.); ld=length(d);
  put "a=" a " len=" la;
  put "b=" b " len=" lb;
  put "c=" c " len=" lc;
  put "d=" d " len=" ld;
run;
