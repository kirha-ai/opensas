/* STAT-LOGISTIC-013: LOGISTIC — ODDSRATIO / UNITS / Odds Ratio Estimation
 * Source: S154 / Chapter 79 / `ODDSRATIO Statement` (PDF pp. 5889–5891); S154 / Chapter 79 / `UNITS Statement` (PDF pp. 5903–5904); S154 / Chapter 79 / `Odds Ratio Estimation` (PDF pp. 5922–5925).
 * Discriminates: Example 79.7: ROC Curve, Customized Odds Ratios, Goodness-of-Fit Statistics, R-Square, and Confidence Limits; explicit statements: UNITS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Data1;
input disease n age id $;
datalines;
0 14 25 a
0 20 35 b
0 19 45 c
7 18 55 d
6 12 65 e
17 17 75 f
;
ods graphics on;
%let _ROC_XAXISOPTS_LABEL=False Positive Fraction;
%let _ROC_YAXISOPTS_LABEL=True Positive Fraction;
proc logistic data=Data1 plots(only)=roc(id=id);
model disease/n=age / scale=none
clparm=wald
clodds=pl
rsquare;
units age=10;
id id;
effectplot;
run;
%symdel _ROC_XAXISOPTS_LABEL _ROC_YAXISOPTS_LABEL;
run;
quit;
