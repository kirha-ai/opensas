/* expect-rc: 1
 * STAT-STDRATE-001: PROC STDRATE BY groups, observation selection and
 * declaration rules for direct rate standardization. Expected text is the
 * SAS 9.4 (SAS/STAT 15.4) listing of this program (reference run
 * 2026-11-28, no titles); the log WARNINGs for reference strata absent from the study
 * (C6, C9) are not part of the listing; they make SAS exit 1. Invented data.
 * C1 BY (reference shared by every group), C2 several observations per
 * stratum add up, C3 no STRATA statement = one stratum, C4 DATA= omitted
 * reads the last data set, C6 reference-only stratum counted but not used,
 * C8 STAT=RATE(MULT=1000), C9 empty study, C11 FORMAT groups STRATA levels
 * (applies to both data sets), C12/C13 identical repeated STRATA/REFERENCE
 * statements, C15 repeated STRATA variable.
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
/* C1 BY */
proc stdrate data=study refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; strata age; by site; run;
/* C2 multiple obs per stratum */
proc stdrate data=study refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; strata age; run;
/* C3 no strata */
data s1; set study; where site=1; run;
proc stdrate data=s1 refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; run;
/* C4 data omitted */
data s1; set study; where site=1; run;
proc stdrate refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; strata age; run;
/* C6 stratum only in reference */
data r6; input age $ total; datalines;
young 20000
old 10000
mid 15000
;
proc stdrate data=s1 refdata=r6 method=direct stat=rate;
population event=event total=total; reference total=total; strata age; run;
/* C8 mult=1000 */
proc stdrate data=s1 refdata=reference method=direct stat=rate(mult=1000);
population event=event total=total; reference total=total; strata age; run;
/* C9 empty study */
data s9; set study; stop; run;
proc stdrate data=s9 refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; strata age; run;
/* C11 format */
proc format; value $agef 'young'='Y' 'old'='O'; run;
proc stdrate data=s1 refdata=reference method=direct stat=rate;
format age $agef.;
population event=event total=total; reference total=total; strata age; run;
/* C12 duplicate strata statement */
proc stdrate data=s1 refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; strata age; strata age; run;
/* C13 duplicate reference statement */
proc stdrate data=s1 refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; reference total=total; strata age; run;
/* C15 repeated strata variable */
proc stdrate data=s1 refdata=reference method=direct stat=rate;
population event=event total=total; reference total=total; strata age age; run;
title;
