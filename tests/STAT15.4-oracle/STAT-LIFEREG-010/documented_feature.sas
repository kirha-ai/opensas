/* STAT-LIFEREG-010: LIFEREG — Predicted Values
 * Source: S154 / Chapter 76 / `Predicted Values` (PDF pp. 5572–5574).
 * Discriminates: Example 76.2: Computing Predicted Values for a Tobit Model
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data subset;
input Hours Yrs_Ed Yrs_Exp @@;
if Hours eq 0
then Lower=.;
else Lower=Hours;
datalines;
0 8 9 0 8 12 0 9 10 0 10 15 0 11 4 0 11 6
1000 12 1 1960 12 29 0 13 3 2100 13 36
3686 14 11 1920 14 38 0 15 14 1728 16 3
1568 16 19 1316 17 7 0 17 15
;
proc lifereg data=subset outest=OUTEST(keep=_scale_);
model (lower, hours) = yrs_ed yrs_exp / d=normal;
output out=OUT xbeta=Xbeta;
run;
data predict;
drop lambda _scale_ _prob_;
set out;
if _n_ eq 1 then set outest;
lambda = pdf('NORMAL',Xbeta/_scale_)
/ cdf('NORMAL',Xbeta/_scale_);
Predict = cdf('NORMAL', Xbeta/_scale_)
* (Xbeta + _scale_*lambda);
label Xbeta='MEAN OF UNCENSORED VARIABLE'
Predict = 'MEAN OF CENSORED VARIABLE';
run;
