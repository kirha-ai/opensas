/* STAT-SURVEYLOGISTIC-001: design variants of PROC SURVEYLOGISTIC (SAS/STAT
 * 15.4 Ch.120 pp.9803-9840): A no WEIGHT; B missing response, covariate,
 * WEIGHT, STRATA and CLUSTER values and a zero weight (observation counts,
 * sums of weights read/used, exclusion notes); C BY groups (listing per
 * group, titles repeated); D FREQ with CLUSTER (frequency rows, totals
 * and frequency-weighted fit, variance and association); E NOPRINT (no listing); F WEIGHT only (no
 * Rao-Scott note, df n-1); G CLUSTER without STRATA. Expected output is the
 * SAS 9.4 listing of this exact program (one real-SAS run, 2026-11-28).
 * The blank page-start line SAS prints before each new page's title is
 * dropped, as in every titled corpus fixture. Data: invented design; the 0/1 responses are the SAS draws for
 * streaminit 722, rand('bernoulli',0.3), written literally. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data survey;
array e{96} _temporary_ (
0 0 1 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 1 0 0 1 0 1 1 0 0 0 1 1 1 1 0 0 0 0 0 0 1 0 0 0 0 0 1 1 0 0 0 1 1 1 0 0 0 0 0 1 0 1 1 0 0 1 1 0 1 0 );
k=0;
do stratum=1 to 2;
do cluster=1 to 4;
do id=1 to 12;
k+1;
age=20+mod(id*7+cluster,45);
event=e{k};
weight=2+stratum+cluster/10;
output;
end;
end;
end;
drop k;
run;
data miss; set survey;
if _n_=3 then event=.;
if _n_=10 then age=.;
if _n_=20 then weight=.;
if _n_=30 then weight=0;
if _n_=40 then stratum=.;
if _n_=50 then cluster=.;
run;
title 'A';
proc surveylogistic data=survey;
strata stratum;
cluster cluster;
model event(event='1')=age;
run;
title 'B';
proc surveylogistic data=miss;
strata stratum;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
title 'C';
proc surveylogistic data=survey;
by stratum;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
title 'D';
data fr; set survey; f=1+mod(_n_,3); run;
proc surveylogistic data=fr;
strata stratum;
cluster cluster;
weight weight;
freq f;
model event(event='1')=age;
run;
title 'E';
proc surveylogistic data=survey noprint;
strata stratum;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
title 'F';
proc surveylogistic data=survey;
weight weight;
model event(event='1')=age;
run;
title 'G';
proc surveylogistic data=survey;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
