/* expect-rc: 1
 * STAT-STDRATE-001: SAS 9.4 reference run (2026-11-28) logs
 * "ERROR: The population rate is missing in the stratum age=young." and prints no listing. Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data study; input site age $ event total; datalines;
1 young 10 1000
1 old 30 1500
;
data reference; input age $ total; datalines;
young 20000
old 10000
;
data refby; input site age $ total; datalines;
1 young 20000
1 old 10000
;
run;
/* D1 missing total */
data d1; input age $ event total; datalines;
young 10 .
old 30 1500
;
proc stdrate data=d1 refdata=reference method=direct; population event=event total=total; reference total=total; strata age; run;
