data a; input k x; datalines;
1 10
2 20
;
run;
data b; input k y; datalines;
1 100
2 200
3 300
;
run;
data _null_;
  merge a(in=ina) b(in=inb);
  put "k=" k "x=" x "y=" y "ina=" ina "inb=" inb;
run;
data _null_;
  merge b(in=inb) a(in=ina);
  put "k=" k "x=" x "y=" y "ina=" ina "inb=" inb;
run;
data keepa;
  merge a(in=ina) b;
  if ina;
run;
proc print data=keepa;
run;
