/* STAT-SURVEYFREQ-001: a missing CLUSTER value alone (Number of Observations is
   the valid count), ORDER=DATA, VARHEADER=LABEL and NAMELABEL column
   headers, character TABLES variables (width = variable length).
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
title 'D1 CLUSTERONLY'; proc surveyfreq data=mc; strata state; cluster school; weight samplingweight; tables schooltype*response; run;
title 'D4 ORDERDATA'; proc surveyfreq data=ord order=data; strata state; cluster school; weight samplingweight; tables schooltype*response; run;
title 'D5 LABEL'; proc surveyfreq data=ord varheader=label; strata state; cluster school; weight samplingweight; tables schooltype*response; run;
title 'D6 NAMELABEL'; proc surveyfreq data=ord varheader=namelabel; strata state; cluster school; weight samplingweight; tables schooltype*response; run;
title 'D8 CHAR'; proc surveyfreq data=chr; strata state; cluster school; weight samplingweight; tables st*respname; run;
