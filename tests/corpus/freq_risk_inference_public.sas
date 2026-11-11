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
