/* PUT a number to text then INPUT it back (format/informat round-trip) */
data d;
  x = 1234.56;
  length s $12;
  s  = put(x, 10.2);
  y  = input(s, 10.2);
  dt = "15JAN2024"d;
  length ds $10;
  ds = put(dt, yymmdd10.);
  dt2 = input(ds, yymmdd10.);
  samenum = (x = y);
  samedt  = (dt = dt2);
  put "samenum=" samenum " samedt=" samedt;
run;
