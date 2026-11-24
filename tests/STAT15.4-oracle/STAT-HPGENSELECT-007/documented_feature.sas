/* STAT-HPGENSELECT-007: HPGENSELECT — PARTITION / SELECTION / The LASSO Method of Model Selection
 * Source: S154 / Chapter 59 / `PARTITION Statement` (PDF pp. 4647–4648); S154 / Chapter 59 / `SELECTION Statement` (PDF pp. 4650–4652); S154 / Chapter 59 / `The LASSO Method of Model Selection` (PDF pp. 4663–4666).
 * Discriminates: Example 59.4: Model Selection by the LASSO Method; explicit statements: SELECTION
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

%let nObs = 1500;
%let nContIn = 5;
%let nContOut = 10;
%let Seed = 12345;
data ex4Data;
array xIn{&nContIn};
array xOut{&nContOut};
drop i j sign xBeta expXbeta;
seed = &Seed;
do i=1 to &nObs;
sign = -1;
xBeta = 0;
do j=1 to dim(xIn);
call ranuni(seed,xIn[j]);
xBeta = xBeta + j *sign*xIn{j};
sign = -sign;
end;
do j=1 to dim(xOut);
call ranuni(seed,xOut[j]);
end;
call ranuni(seed,xSubtle);
call ranuni(seed,xTiny);
xBeta = xBeta + 0.1*xSubtle + 0.05*xTiny;
expXbeta = exp(xBeta/20);
call ranpoi(seed,expXbeta,yPoisson);
output;
end;
run;
proc hpgenselect data=ex4Data(Obs=10000);
model yPoisson = x: / dist=Poisson;
selection method=Lasso(choose=SBC) details=all;
performance details;
run;
