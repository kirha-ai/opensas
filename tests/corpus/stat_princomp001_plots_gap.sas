/* expect-rc: 2
   STAT-PRINCOMP-001 boundary: the correlation analysis itself is computed,
   but ODS Graphics output (the default scree plot and the PLOTS=SCORE
   request, STAT-PRINCOMP-006) is not implemented. The step (the shape of the
   reference program) must fail visibly (D-009 gap) and print no table and
   create no OUT= data set, never a listing with silently missing graphs.
   Data: the published crime-rates sample of ch.98 (first eight states). */
options nocenter linesize=160;
title;
data Crime;
input State $1-15 Murder Rape Robbery Assault
Burglary Larceny Auto_Theft;
datalines;
Alabama         14.2 25.2 96.8 278.3 1135.5 1881.9 280.7
Alaska          10.8 51.6 96.8 284.0 1331.7 3369.8 753.3
Arizona         9.5 34.2 138.2 312.3 2346.1 4467.4 439.5
Arkansas        8.8 27.6 83.2 203.4 972.6 1862.1 183.4
California      11.5 49.4 287.0 358.0 2139.4 3499.8 663.5
Colorado        6.3 42.0 170.7 292.9 1935.2 3903.2 477.1
Connecticut     4.2 16.8 129.5 131.8 1346.0 2620.7 593.2
Delaware        6.0 24.9 157.0 194.2 1682.6 3678.4 467.0
;
ods graphics on;
proc princomp out=Crime_Components plots= score(ellipse ncomp=3);
id State;
run;
