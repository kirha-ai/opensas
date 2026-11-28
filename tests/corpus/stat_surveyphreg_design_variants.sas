/* STAT-SURVEYPHREG-001: design variants and NOPRINT. Invented deterministic
 * data (2 strata x 3 clusters x 8 subjects). Expected text: SAS 9.4 (SAS/STAT
 * 15.4) listing of this program. Cases: no WEIGHT (weights 1), STRATA only
 * (each observation its own PSU, df = n - H), CLUSTER only (one stratum,
 * df = clusters - 1), no design statements (df = n - 1, no Design Summary),
 * NOPRINT (no output), one observation excluded only by a missing WEIGHT.
 * The SAS run titled each step ('A noweight' ...); the title lines and the
 * blank page-break line before them are removed from the expected text. */
title;
data s;
do stratum=1 to 2;
do cluster=1 to 3;
do id=1 to 8;
age=20+mod(id*7+cluster*3,31);
time=1+mod(id*13+cluster*5+stratum*3,17)+id/10;
status=(mod(id,3) ne 0);
weight=1+stratum+cluster/4;
output;
end;
end;
end;
run;
data s2; set s; if _n_=5 then weight=.; run;
proc surveyphreg data=s; strata stratum; cluster cluster; model time*status(0)=age; run;
proc surveyphreg data=s; strata stratum; weight weight; model time*status(0)=age; run;
proc surveyphreg data=s; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=s; model time*status(0)=age; run;
proc surveyphreg data=s noprint; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
proc surveyphreg data=s2; strata stratum; cluster cluster; weight weight; model time*status(0)=age; run;
