/* STAT-PLM-008: PLM — CODE / SCORE / Scoring Data Sets for Zero-Inflated Models
 * Source: S154 / Chapter 94 / `CODE Statement` (PDF pp. 7632–7633); S154 / Chapter 94 / `SCORE Statement` (PDF pp. 7639–7641); S154 / Chapter 94 / `Scoring Data Sets for Zero-Inflated Models` (PDF p. 7648).
 * Discriminates: Example 94.1: Scoring with PROC PLM; explicit statements: SCORE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

%let nObs = 5000;
%let nVars = 100;
data SimuData;
array x{&nVars};
do obsNum=1 to &nObs;
do j=1 to &nVars;
x{j}=ranuni(1);
end;
linp = 10 + 11 *x1 - 10*sqrt(x2) + 2/x3 - 8*exp(x4) + 7*x5*x5
- 6*x6**1.5 + 5*log(x7) - 4*sin(3.14*x8) + 3*x9 - 2*x10;
TrueProb = 1/(1+exp(-linp));
if ranuni(1) < TrueProb then y=1;
else y=0;
output;
end;
run;
proc logistic data=SimuData;
effect splines = spline(x1-x&nVars/separate);
model y = splines/selection=stepwise;
store work.SimuModel;
run;
data test;
array x{&nVars};
do j=1 to &nVars;
x{j}=0.15;
end;
drop j;
output;
run;
proc plm restore=work.SimuModel;
score data=test out=testout predicted / ilink;
run;
