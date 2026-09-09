/* Rounding family on a lab ratio (ROUND to a unit, CEIL/FLOOR/INT) */
data lb;
  input AVAL ULN;
  ratio = AVAL / ULN;
  r1    = round(ratio, 0.1);
  r2    = round(ratio, 0.01);
  up    = ceil(ratio);
  dn    = floor(ratio);
  tr    = int(ratio);
  datalines;
137 40
28 40
;
run;
proc print data=lb; var ratio r1 r2 up dn tr; run;
