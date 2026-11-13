/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(p=.2 var=null) alpha=.6; run;
proc freq data=b; weight w; tables x / noprint bin(cl=(ac exact jeffreys lr logit midp wald wilson)) alpha=.1; run;
proc freq data=b; weight w; tables x / noprint binomial(level=2 p=1 correct cl=(wald wilson)); run;

/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / noprint senspec riskdiff relrisk; run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks cl=(ac ha mn newcombe wald)) relrisk(cl=(wald waldmodified score lr)) or(cl=(wald waldmodified score lr midp)); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks column=2 cl=(mn(correct=no) newcombe(correct) wald(correct))) relrisk(column=2 cl=(waldmodified score(correct=no) lr)); run;

/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=b; weight w; tables x / noprint binomial(equiv p=.5 margin=(-.3,.1) var=null correct); run;
proc freq data=b; weight w; tables x / noprint binomial(noninf p=.5 margin=.2); run;
proc freq data=b; weight w; tables x / noprint binomial(sup p=.2 margin=.1 var=null); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks equiv margin=(-.1,.6) method=wald); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks equiv margin=(-.1,.6) method=ha); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks equiv margin=(-.1,.6) method=fm); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks equiv margin=(-.1,.6) method=newcombe); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(equiv margin=(.8,5) method=wald); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(equiv margin=(.8,5) method=waldmodified); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(equiv margin=(.8,5) method=fm); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(equiv margin=(.8,5) method=lr); run;

/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
proc format; value event 1='Event' 2='Other'; run;
data b; input g x w; datalines;
1 1 7
1 2 13
2 1 0
2 2 10
;
proc freq data=b order=freq; by g; weight w / zeros; format x event.; tables x / noprint binomial(level='Event' cl=(exact logit wilson)); run;
proc freq data=b noprint; by g; weight w / zeros; tables x / binomial; run;

/* FEAT-freq-risk independent SAS evidence: /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/aliases.{sas,txt,log}. SAS/STAT pp108-112,145-149,176-209. */
options nodate nonumber nosyntaxcheck; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=b; weight w; tables x / noprint bin(level='2' p=50 cl=(agresticoull clopperpearson likelihoodratio score(correct))); run;
proc freq data=b; weight w; tables x / noprint binomial(equivalence margin=(-30,10) var=sample); run;
proc freq data=t; weight w; tables r*c / noprint oddsratio(cl=(score(correct=no) likelihoodratio)); run;
proc freq data=t; weight w; tables r*c / noprint riskdiff(norisks column=both equal(null=-1) method=score cl=(agresticaffo score(mee))); run;
proc freq data=t; weight w; tables r*c / noprint relrisk(equivalence margin=.8 method=score); run;
data boundary; input x w; datalines;
1 10
2 0
;
proc freq data=boundary; weight w / zeros; tables x / noprint binomial(var=sample cl=(wald exact logit lr wilson)); run;

options nodate nonumber nosyntaxcheck; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(p=.2 var=null) alpha=.6; run;
proc freq data=b; weight w; tables x / noprint binomial(p=.2 var=null) alpha=.05; run;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / noprint riskdiff(column=both equal(null=10) var=null) relrisk(equal(null=2) printall) alpha=.6; run;

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

/* FEAT-freq-risk independent SAS evidence: /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/correction-direction.{sas,txt,log}. SAS/STAT pp108-112,145-149,176-209. */
options nodate nonumber nosyntaxcheck; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(p=.35 correct); run;
proc freq data=b; weight w; tables x / noprint binomial(p=.34 correct); run;
proc freq data=b; weight w; tables x / noprint binomial(p=.36 correct); run;

/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(cl=wilson(correct)); run;
proc freq data=b; weight w; tables x / noprint binomial(cl=wald(correct)); run;
data f; input x w; datalines;
1 1.9
2 8.7
;
proc freq data=f; weight w; tables x / noprint binomial; run;
data z; input r c w; datalines;
1 1 0
1 2 10
2 1 5
2 2 5
;
proc freq data=z; weight w / zeros; tables r*c / noprint or(cl=(wald waldmodified score lr)) relrisk(cl=(wald waldmodified score lr)); run;

/* FEAT-freq-risk numerical boundary acceptance; independent SAS evidence acceptance/boundaries-public.{sas,txt,log}. */
options nodate nonumber nosyntaxcheck; ods graphics off;
data allrow1; input r c w; datalines;
1 1 10
1 2 0
2 1 5
2 2 5
;
proc freq data=allrow1; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=allrow1; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;
data zerorow2; input r c w; datalines;
1 1 5
1 2 5
2 1 0
2 2 10
;
proc freq data=zerorow2; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=zerorow2; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;
data fractional; input r c w; datalines;
1 1 12.4
1 2 8.6
2 1 5.2
2 2 25.8
;
proc freq data=fractional; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=fractional; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;
data extreme; input r c w; datalines;
1 1 1
1 2 999
2 1 2
2 2 998
;
proc freq data=extreme; weight w / zeros; tables r*c / noprint senspec or(cl=(score lr)) relrisk(cl=(score lr)) riskdiff(norisks cl=(wald ac ha mn newcombe)); run;
proc freq data=extreme; weight w / zeros; tables r*c / noprint relrisk(column=2 cl=(wald waldmodified score lr)); run;

options nodate nonumber; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(noninf margin=.2) alpha=.6; run;
data t; input r c w; datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
proc freq data=t; weight w; tables r*c / noprint riskdiff(noninf method=newcombe) relrisk(equiv method=score) alpha=.6; run;
