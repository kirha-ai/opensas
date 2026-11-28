/* expect-rc: 1
 * STAT-STDRATE-001: a study stratum whose only observation has a missing
 * EVENT= value stops the step. SAS 9.4 reference run (2026-11-28) logs
 * "ERROR: The population rate is missing in the stratum age=young." and
 * prints no listing. Invented data.
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
title 'C5 missing event';
data s5; input age $ event total; datalines;
young . 1000
old 30 1500
mid 20 1200
;
data r5; input age $ total; datalines;
young 20000
old 10000
mid 15000
;
proc stdrate data=s5 refdata=r5 method=direct stat=rate;
population event=event total=total; reference total=total; strata age; run;
title;
