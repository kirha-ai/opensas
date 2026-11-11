/* FEAT-freq-risk independent SAS evidence: /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/tests-remaining.{sas,txt,log}. SAS/STAT pp108-112,145-149,176-209. */
options nodate nonumber nosyntaxcheck; ods graphics off;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks noninferiority margin=20 method=wald); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks superiority margin=20 method=wald); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks noninferiority margin=20 method=ha); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks superiority margin=20 method=ha); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks noninferiority margin=20 method=fm); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks superiority margin=20 method=fm); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks noninferiority margin=20 method=newcombe); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks superiority margin=20 method=newcombe); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks noninf margin=.2 var=null correct); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks equiv margin=(-.1,.6) var=null correct); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(noninf margin=0.8 method=wald); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(sup margin=1.25 method=wald); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(noninf margin=0.8 method=waldmodified); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(sup margin=1.25 method=waldmodified); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(noninf margin=0.8 method=score); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(sup margin=1.25 method=score); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(noninf margin=0.8 method=likelihoodratio); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(sup margin=1.25 method=likelihoodratio); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(equal(null=2) method=lr); run;
