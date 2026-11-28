/* expect-rc: 2
 * STAT-CLUSTER-001: valid PROC CLUSTER requests outside the implemented path
 * fail visibly (D-009 gap) and print nothing; here METHOD=DENSITY (owned by
 * STAT-CLUSTER-003). The other gaps are Zig tests in src/stat/cluster_tests.zig.
 * Published flying-mileage data.
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
proc cluster data=mileages(type=distance) method=density k=3;
   id City;
run;
