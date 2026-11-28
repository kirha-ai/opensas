/* expect-rc: 1
 * STAT-STDRATE-001: PROC STDRATE observation selection. Expected text is the
 * SAS 9.4 (SAS/STAT 15.4) listing of this program (reference run
 * 2026-11-28, no titles). D2: a missing EVENT= value adds no events while
 * its TOTAL= still counts; D5: DATA=(WHERE=) selects study observations only
 * (the unmatched reference stratum draws a WARNING, so SAS exits 1); D7: two
 * STRATA variables, a reference-only combination is counted but not used.
 * Invented data.
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
/* D2 missing event beside other obs */
data d2; input age $ event total; datalines;
young 10 1000
young . 500
old 30 1500
;
proc stdrate data=d2 refdata=reference method=direct; population event=event total=total; reference total=total; strata age; run;
/* D5 data set option */
proc stdrate data=study(where=(age='young')) refdata=reference method=direct; population event=event total=total; reference total=total; strata age; run;
/* D7 two strata vars message */
data d7; input sex $ age $ event total; datalines;
F young 10 1000
F old 30 1500
;
data r7; input sex $ age $ total; datalines;
F young 20000
F old 10000
M old 10000
;
proc stdrate data=d7 refdata=r7 method=direct; population event=event total=total; reference total=total; strata sex age; run;
