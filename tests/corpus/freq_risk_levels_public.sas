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
