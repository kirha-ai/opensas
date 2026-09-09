/* SUM/MEAN/N/NMISS ignore missing arguments */
data d; input a b c; datalines;
10 . 30
. . 5
1 2 3
;
run;
data agg;
  set d;
  s  = sum(a, b, c);
  m  = mean(a, b, c);
  nn = n(a, b, c);
  nm = nmiss(a, b, c);
run;
proc print data=agg; var a b c s m nn nm; run;
