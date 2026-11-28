/* STAT-SURVEYLOGISTIC-001: PROC SURVEYLOGISTIC binary logit with STRATA,
 * CLUSTER and WEIGHT under Taylor-series variance (SAS/STAT 15.4 Ch.120).
 * The 0/1 responses are the published draws of the chapter-style example
 * (streaminit 722, rand('bernoulli',0.3)) written out literally, so the
 * expected listing is the SAS reference listing independent of the RNG.
 * Data: invented design. */
options nodate nonumber nocenter linesize=160;
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
proc surveylogistic data=survey;
strata stratum;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
