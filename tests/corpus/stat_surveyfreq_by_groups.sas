/* STAT-SURVEYFREQ-001: BY-group processing: one Data Summary and table per BY group, the title
   repeated before each group, the BY line flush left (NOCENTER).
   Expected listing: real SAS 9.4 / SAS/STAT 15.4 run of this program
   (batched reference run, 2026-11-28). Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data survey;
do state=1 to 2;
do school=1 to 4;
do id=1 to 6;
response=1+mod(id+school,3);
schooltype=1+mod(school,2);
samplingweight=2+state+school/10;
output;
end;
end;
end;
run;
data miss; set survey;
if _n_=3 then samplingweight=.;
if _n_=5 then samplingweight=0;
if _n_=7 then school=.;
if _n_=9 then response=.;
run;
data single; set survey; if state=2 and school>1 then delete; run;
data chr; set survey; length st $4 resp $3; st=put(schooltype,1.)||'x'; resp=put(response,1.); run;
title 'CASE1 BY'; proc surveyfreq data=survey; by state; cluster school; weight samplingweight; tables schooltype*response / row; run;
