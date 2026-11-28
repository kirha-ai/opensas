/* STAT-RMSTREG-001: PROC RMSTREG statement options, MODEL roles and the
 * selection rules against SAS 9.4 listings (invented deterministic data):
 * default TAU= (largest event time) and LINK=LOG; ALPHA= with NOINT; no
 * censoring variable; a censoring value list; NOPRINT; FREQ truncation with
 * missing time, negative time, missing FREQ, FREQ 0, missing censoring
 * value; TAU= beyond the largest time (WARNING in the log); a name longer
 * than NAMELEN=20 with MODEL ALPHA= overriding PROC ALPHA=; two MODEL
 * statements (the first is fitted); an intercept-only model.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data d;
do id=1 to 60;
age=25+mod(id*7,40);
x=mod(id,2);
time=exp(0.5+0.15*x+0.01*age+0.7*sin(id*1.7));
status=(mod(id,4) ne 0);
f=1+mod(id,3);
output;
end;
label time='Survival Time';
run;
proc rmstreg data=d; model time*status(0)=age x; run;
proc rmstreg data=d tau=4 alpha=0.1; model time*status(0)=age x / noint link=linear; run;
proc rmstreg data=d tau=4; model time=age x / link=linear; run;
proc rmstreg data=d tau=4; model time*f(1,3)=age / link=linear; run;
proc rmstreg data=d tau=4 noprint; model time*status(0)=age x; run;
data e; set d; if id=3 then time=.; if id=4 then time=-1; if id=5 then f=.; if id=6 then f=0; if id=8 then f=2.7; if id=9 then status=.; run;
proc rmstreg data=e tau=4; freq f; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=30; model time*status(0)=age x / link=linear; run;
data g; set d; averylongcovariatename_abc=age; run;
proc rmstreg data=g tau=4 alpha=0.2; model time*status(0)=averylongcovariatename_abc x / alpha=0.1 link=linear; run;
proc rmstreg data=d tau=4; model time*status(0)=age / link=linear; model time*status(0)=x / link=linear; run;
proc rmstreg data=d tau=4; model time*status(0)= / link=linear; run;
