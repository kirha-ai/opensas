/* STAT-SURVEYFREQ-001: stratified cluster design with sampling weights;
   Data Summary and a two-way table with ROW (weighted frequency, its standard
   deviation, percent, row percent and their Taylor-series standard errors),
   plus CHISQ on a table whose design correction is not positive, so the
   Rao-Scott test is reported as not computable. Expected listing is the SAS
   reference listing for this program. Data: invented, generated in the step. */
options nodate nonumber nocenter linesize=160;
title;
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
proc surveyfreq data=survey;
strata state;
cluster school;
weight samplingweight;
tables schooltype*response / row chisq;
run;
