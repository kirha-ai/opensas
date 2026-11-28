/* expect-rc: 1
 * STAT-CLUSTER-001: invalid PROC CLUSTER input is rejected with an ERROR and
 * no listing: METHOD= missing (required, p.2486), a missing value in the lower
 * triangle and a row/variable mismatch of a TYPE=DISTANCE data set (p.2509),
 * a character VAR variable, an unknown ID variable, RMSSTD without FREQ.
 * Published flying-mileage data plus invented rows.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
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
proc cluster data=mileages(type=distance);
   id City;
run;
data holes; set mileages; if City = 'Denver' then Chicago = .; run;
proc cluster data=holes(type=distance) method=average;
   id City;
run;
data short; set mileages; if _n_ <= 9; run;
proc cluster data=short(type=distance) method=average;
   id City;
run;
proc cluster data=mileages(type=distance) method=average;
   var Atlanta City;
run;
proc cluster data=mileages(type=distance) method=average;
   id Town;
run;
data f; set mileages; n = 1; s = 0; run;
proc cluster data=f(type=distance) method=average;
   rmsstd s;
   id City;
run;
