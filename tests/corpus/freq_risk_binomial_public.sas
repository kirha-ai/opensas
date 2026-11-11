/* FEAT-freq-risk public intermediate. Independent sasrun evidence /tmp/opensas-stat-batch2/FEAT-freq-risk/public/; numerical comparisons at printed precision. Full exact/common ticket acceptance remains pending. */
options nodate nonumber; ods graphics off;
data b; input x w; datalines;
1 7
2 13
;
proc freq data=b; weight w; tables x / noprint binomial(p=.2 var=null) alpha=.6; run;
proc freq data=b; weight w; tables x / noprint bin(cl=(ac exact jeffreys lr logit midp wald wilson)) alpha=.1; run;
proc freq data=b; weight w; tables x / noprint binomial(level=2 p=1 correct cl=(wald wilson)); run;
