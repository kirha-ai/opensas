/* STAT-RMSTREG-001 close-out: data input, BY, FREQ and PROC options against
 * the SAS 9.4 listing of this exact program (invented deterministic data,
 * 2026-11-28 batch): an input data set without observations (NOTE, no
 * listing); a WHERE statement selecting nothing (NOTE, no listing); two FREQ statements (the first is used); BY DESCENDING; BY
 * NOTSORTED; two BY statements (the last is used); DATA= omitted (the most
 * recent data set); a WHERE statement; PROC ALPHA=0 (100% limits, z =
 * probit(1-1e-15)); PROC ALPHA=1 (0% limits on one header line); MODEL
 * ALPHA=0 overriding PROC ALPHA=0.1; ALPHA=1e-12 (z = probit(1-5e-13));
 * SINGULAR=0; ALPHA=1e-16 (clamped like 0); ALPHA=0.00001234 (the header
 * label wraps as "99.998766%" / "Confidence Limits").
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data d;
do id=1 to 60;
age=25+mod(id*7,40);
x=mod(id,2);
time=round(exp(0.5+0.15*x+0.01*age+0.7*sin(id*1.7)),0.001);
status=(mod(id,4) ne 0);
f=1+mod(id,3);
g=mod(id,3);
output;
end;
run;
data empty; set d; stop; run;
proc rmstreg data=empty tau=4; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=4; where id>1000; model time*status(0)=age x / link=linear; run;
title 'Two FREQ statements';
proc rmstreg data=d tau=4; freq f; freq g; model time*status(0)=age x / link=linear; run;
title 'BY DESCENDING';
proc sort data=d out=sd; by descending g; run;
proc rmstreg data=sd tau=4; by descending g; model time*status(0)=age x / link=linear; run;
title 'BY NOTSORTED';
proc rmstreg data=sd tau=4; by g notsorted; model time*status(0)=age x / link=linear; run;
title 'Two BY statements';
proc sort data=d out=sx; by x; run;
proc rmstreg data=sx tau=4; by g; by x; model time*status(0)=age / link=linear; run;
title 'DATA= omitted';
data last; set d; run;
proc rmstreg tau=4; model time*status(0)=age x / link=linear; run;
title 'WHERE';
proc rmstreg data=d tau=4; where id>10; model time*status(0)=age x / link=linear; run;
title 'ALPHA=0';
proc rmstreg data=d tau=4 alpha=0; model time*status(0)=age x / link=linear; run;
title 'ALPHA=1';
proc rmstreg data=d tau=4 alpha=1; model time*status(0)=age x / link=linear; run;
title 'MODEL ALPHA=0';
proc rmstreg data=d tau=4 alpha=0.1; model time*status(0)=age x / link=linear alpha=0; run;
title 'ALPHA=1e-12';
proc rmstreg data=d tau=4 alpha=1e-12; model time*status(0)=age x / link=linear; run;
title 'SINGULAR=0';
proc rmstreg data=d tau=4 singular=0; model time*status(0)=age x / link=linear; run;
title 'ALPHA=1e-16';
proc rmstreg data=d tau=4 alpha=1e-16; model time*status(0)=age x / link=linear; run;
title 'ALPHA=0.00001234';
proc rmstreg data=d tau=4 alpha=0.00001234; model time*status(0)=age x / link=linear; run;
