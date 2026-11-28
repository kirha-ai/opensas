/* expect-rc: 1
 * STAT-SURVEYLOGISTIC-001: more design rules of PROC SURVEYLOGISTIC (SAS/STAT
 * 15.4 Ch.120 pp.9803-9840): I two STRATA variables (Stratum Variables
 * header, strata crossed); K FREQ values truncated, zero/missing FREQ and a
 * negative WEIGHT excluded (sums of frequencies and weights read/used, one
 * combined note); M singular exclusion notes and a second WEIGHT statement
 * ignored (p.9827); N an empty input data set: ERROR, no listing, rc 1.
 * Expected output is the SAS 9.4 listing of this exact program (one real-SAS
 * run, 2026-11-28); the blank page-start line before each new page's title
 * is dropped as in every titled corpus fixture. Data: invented design; the
 * 0/1 responses are the SAS draws for streaminit 722,
 * rand('bernoulli',0.3), written literally. */
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
data s2; set survey; half=(id>6); run;
title 'I';
proc surveylogistic data=s2;
strata stratum half;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
data fr2; set survey; f=1+mod(_n_,3); if _n_=5 then f=0; if _n_=6 then f=.; if _n_=7 then f=2.7; if _n_=8 then weight=-1; run;
title 'K';
proc surveylogistic data=fr2;
strata stratum;
cluster cluster;
weight weight;
freq f;
model event(event='1')=age;
run;
data one; set survey; if _n_=4 then age=.; if _n_=9 then weight=0; run;
title 'M';
proc surveylogistic data=one;
strata stratum;
cluster cluster;
weight weight;
weight age;
model event(event='1')=age;
run;
data empty; set survey; stop; run;
title 'N';
proc surveylogistic data=empty;
strata stratum;
cluster cluster;
weight weight;
model event(event='1')=age;
run;
