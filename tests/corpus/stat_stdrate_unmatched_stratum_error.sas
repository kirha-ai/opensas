/* expect-rc: 1
 * STAT-STDRATE-001: a study stratum absent from the REFDATA= data set stops
 * the step. SAS 9.4 reference run (2026-11-28) logs "ERROR: The reference
 * total is missing in the stratum age=mid." and prints no listing.
 * Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data study;
input site age $ event total;
datalines;
1 young 10 1000
1 old 30 1500
2 young 12 1100
2 old 25 1400
;
data reference;
input age $ total;
datalines;
young 20000
old 10000
;
run;
title 'C14 stratum only in study';
data s14; input age $ event total; datalines;
young 10 1000
old 30 1500
mid 5 800
;
proc stdrate data=s14 refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; strata age; run;
title;
