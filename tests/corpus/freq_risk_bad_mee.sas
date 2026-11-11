/* expect-rc: 1. FEAT-freq-risk independent SAS evidence: /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/invalid-mee.{sas,txt,log}. SAS/STAT pp108-112,145-149,176-209. */
options nodate nonumber nosyntaxcheck; ods graphics off;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks cl=mn(correct=mee)); run;
