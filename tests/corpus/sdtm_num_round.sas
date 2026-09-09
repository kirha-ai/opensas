/* Rounding family on a lab ratio (ROUND/CEIL/FLOOR/INT) */
data lb;
  input AVAL BASE;
  datalines;
45.67 40
133.3 40
;
run;
data d;
  set lb;
  ratio = AVAL / BASE;
  r2    = round(ratio, 0.01);
  up    = ceil(ratio);
  down  = floor(ratio);
  whole = int(ratio);
run;
proc print data=d; var ratio r2 up down whole; run;
