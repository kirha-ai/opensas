/* STAT-SURVEYPHREG-001: PROC SURVEYPHREG Taylor-series listing of a stratified,
 * clustered, weighted Cox model: the default design, observations excluded by
 * missing MODEL / CLUSTER and missing or zero WEIGHT values, a BY statement
 * over two groups, and a FREQ statement. Data: invented. Expected text: SAS
 * reference listing (SAS 9.4, SAS/STAT 15.4), token for token; the BY lines
 * follow the opensas centering convention.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data small;
input st psu w t c x;
datalines;
1 1 2 5.1 1 1.2
1 1 2 3.4 0 0.5
1 1 2 7.7 1 2.1
1 2 3 2.2 1 0.3
1 2 3 9.0 1 1.9
1 2 3 4.6 0 1.1
1 3 1 6.3 1 0.7
1 3 1 1.8 1 2.4
2 1 4 8.1 1 1.6
2 1 4 2.9 1 0.2
2 1 4 5.5 0 1.3
2 2 2 3.7 1 2.2
2 2 2 6.8 1 0.9
2 2 2 4.4 1 1.7
2 3 5 7.2 0 0.4
2 3 5 1.5 1 1.0
2 3 5 5.9 1 2.6
;
proc surveyphreg data=small;
strata st; cluster psu; weight w;
model t*c(0)=x;
run;
data miss; set small; output;
if _n_=1 then do; t=.; output; t=4; x=.; output; x=1; w=0; output; w=.; output; w=2; psu=.; output; end;
run;
proc surveyphreg data=miss;
strata st; cluster psu; weight w;
model t*c(0)=x;
run;
data byd; set small; g=1; output; g=2; t=t*1.3-mod(_n_,3); if t<0.1 then t=0.1; output; run;
proc sort data=byd; by g; run;
proc surveyphreg data=byd;
by g; strata st; cluster psu; weight w;
model t*c(0)=x;
run;
data fq; set small; f=1+mod(_n_,3); run;
proc surveyphreg data=fq;
strata st; cluster psu; weight w; freq f;
model t*c(0)=x;
run;
