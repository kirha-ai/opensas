/* Two-way crosstab, SAS-default 4-stat cells (Frequency, Percent, Row Pct, Col
   Pct) + legend box + marginal totals (FREQ-crosstabpct). Hand-verified:
   grand=8, rowTot DRUG=4 PLAC=4, colTot N=5 Y=3.
     DRUG,N: 2  cell 25.00  row 50.00  col 2/5=40.00
     DRUG,Y: 2  cell 25.00  row 50.00  col 2/3=66.67
     PLAC,N: 3  cell 37.50  row 75.00  col 3/5=60.00
     PLAC,Y: 1  cell 12.50  row 25.00  col 1/3=33.33
   marginals: N 5 (62.50), Y 3 (37.50), grand 8 (100.00). */
data d;
  input trt $ resp $;
  datalines;
DRUG Y
DRUG Y
DRUG N
DRUG N
PLAC Y
PLAC N
PLAC N
PLAC N
;
run;
proc freq data=d;
  tables trt*resp;
run;
