/* STAT-CLUSTER-001: PROC CLUSTER on the published flying-mileage TYPE=DISTANCE
 * data (SAS/STAT 15.4 ch.40 Getting Started / SASHELP.MILEAGES values) with
 * METHOD=AVERAGE, CENTROID, SINGLE and WARD, PSEUDO and an ID variable.
 * Expected tokens are the SAS 9.4 reference listing sections of those methods.
 */
options nodate nonumber nocenter linesize=160;
title; footnote;
data mileages;
   length City $15;
   infile datalines dlm=',';
   input Atlanta Chicago Denver Houston LosAngeles Miami NewYork SanFran Seattle WashDC City $;
   datalines;
0,.,.,.,.,.,.,.,.,.,Atlanta
587,0,.,.,.,.,.,.,.,.,Chicago
1212,920,0,.,.,.,.,.,.,.,Denver
701,940,879,0,.,.,.,.,.,.,Houston
1936,1745,831,1374,0,.,.,.,.,.,Los Angeles
604,1188,1726,968,2339,0,.,.,.,.,Miami
748,713,1631,1420,2451,1092,0,.,.,.,New York
2139,1858,949,1645,347,2594,2571,0,.,.,San Francisco
2182,1737,1021,1891,959,2734,2408,678,0,.,Seattle
543,597,1494,1220,2300,923,205,2442,2329,0,Washington D.C.
;
title 'Cluster Analysis of Flying Mileages Between 10 American Cities';
title2 'Using METHOD=AVERAGE';
proc cluster data=mileages(type=distance) method=average pseudo;
id City;
run;
title2 'Using METHOD=CENTROID';
proc cluster data=mileages(type=distance) method=centroid pseudo;
id City;
run;
title2 'Using METHOD=SINGLE';
proc cluster data=mileages(type=distance) method=single;
id City;
run;
title2 'Using METHOD=WARD';
proc cluster data=mileages(type=distance) method=ward pseudo;
id City;
run;
