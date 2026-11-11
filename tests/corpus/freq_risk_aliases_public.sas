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
