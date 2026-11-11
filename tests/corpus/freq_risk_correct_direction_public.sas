/* FEAT-freq-risk independent SAS evidence: /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/correction-direction.{sas,txt,log}. SAS/STAT pp108-112,145-149,176-209. */
options nodate nonumber nosyntaxcheck; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(p=.35 correct); run;
proc freq data=b; weight w; tables x / noprint binomial(p=.34 correct); run;
proc freq data=b; weight w; tables x / noprint binomial(p=.36 correct); run;
