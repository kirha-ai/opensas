/* STAT-SURVEYPHREG-001: design and missing-value rules. Invented
 * deterministic data (2 strata x 3 clusters x 8 subjects). Expected text: the
 * SAS 9.4 (SAS/STAT 15.4) listing of this program, run with one TITLE per
 * step; the title lines and their page-break blank lines are removed.
 * Cases: two censoring values; two STRATA and two CLUSTER variables; one
 * observation excluded only by a zero WEIGHT, a missing CLUSTER, a negative
 * WEIGHT; MISSING (a missing stratum is a level; it has one cluster and draws
 * the single-cluster WARNING); FREQ with a zero and a missing frequency
 * (excluded, weights still read); a stratum with one cluster (no variance
 * contribution, df unchanged); MODEL without a censoring variable; FREQ with
 * one observation excluded by a missing covariate and one by a zero frequency
 * (frequencies read count the first, not the second).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data s;
do stratum=1 to 2;
do cluster=1 to 3;
do id=1 to 8;
age=20+mod(id*7+cluster*3,31);
time=1+mod(id*13+cluster*5+stratum*3,17)+id/10;
status=mod(id,3);
weight=1+stratum+cluster/4;
sub=mod(id,2);
fq=1+mod(id,3);
output;
end;
end;
end;
run;
data z; set s; if _n_=3 then weight=0; run;
data mc; set s; if _n_=3 then cluster=.; run;
data ms; set s; if _n_=3 then stratum=.; run;
data mf; set s; if _n_=3 then fq=0; if _n_=4 then fq=.; run;
data e; set s; stop; run;
data one; set s; if stratum=2 and cluster>1 then delete; run;
data ng; set s; if _n_=3 then weight=-1; run;
proc surveyphreg data=s; strata stratum; cluster cluster; weight weight; model time*status(0,2)=age; run;
proc surveyphreg data=s; strata stratum sub; cluster cluster id; weight weight; model time*status(0)=age; run;
proc surveyphreg data=z; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=mc; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=ms missing; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=mf; strata stratum; cluster cluster; weight weight; freq fq; model time*status(0)=age; run;
proc surveyphreg data=one; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=ng; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=s; strata stratum; cluster cluster; weight weight; model time=age; run;
data fm; set s; if _n_=3 then age=.; if _n_=4 then fq=0; run;
proc surveyphreg data=fm; strata stratum; cluster cluster; weight weight; freq fq; model time*status(0)=age; run;
