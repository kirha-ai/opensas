/* expect-rc: 1
 * STAT-STDRATE-001: SAS 9.4 reference run (2026-11-28) logs
 * "ERROR: The reference total is missing in the stratum n=               3." and prints no listing. Invented data.
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
/* D6 numeric strata message */
data d6; input n event total; datalines;
1 10 1000
2 30 1500
3 5 900
;
data r6; input n total; datalines;
1 20000
2 10000
;
proc stdrate data=d6 refdata=r6 method=direct; population event=event total=total; reference total=total; strata n; run;
