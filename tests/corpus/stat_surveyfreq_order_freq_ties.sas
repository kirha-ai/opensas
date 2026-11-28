/* STAT-SURVEYFREQ-001: ORDER=FREQ with tied frequencies: ties keep the order of
   first appearance in the data.
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
data mc; set survey; if _n_=7 then school=.; run;
data mr; set survey; if _n_ in (9,20) then response=.; run;
data ord; set survey; response=4-response; if _n_ in (2,3,4) then schooltype=2; label schooltype='Type of School' response='Answer'; run;
data rates; input state _rate_; datalines;
1 0.1
2 0.2
;
data chr; set survey; length st $1 respname $12; st=put(schooltype,1.); respname=put(response,1.); run;
title 'D3 ORDERFREQ'; proc surveyfreq data=ord order=freq; strata state; cluster school; weight samplingweight; tables schooltype*response; run;
