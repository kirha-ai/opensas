/* STAT-NLMIXED-011: NLMIXED — CONTRAST / ESTIMATE
 * Source: S154 / Chapter 89 / `CONTRAST Statement` (PDF p. 7121); S154 / Chapter 89 / `ESTIMATE Statement` (PDF pp. 7121–7122).
 * Discriminates: Example 89.4: Poisson-Normal Model with Count Data; explicit statements: ESTIMATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data pump;
input y t group;
pump = _n_;
logtstd = log(t) - 2.4564900;
datalines;
5 94.320 1
1 15.720 2
5 62.880 1
14 125.760 1
3 5.240 2
19 31.440 1
1 1.048 2
1 1.048 2
4 2.096 2
22 10.480 2
;
proc nlmixed data=pump;
parms logsig 0 beta1 1 beta2 1 alpha1 1 alpha2 1;
if (group = 1) then eta = alpha1 + beta1*logtstd + e;
else eta = alpha2 + beta2*logtstd + e;
lambda = exp(eta);
model y ~ poisson(lambda);
random e ~ normal(0,exp(2*logsig)) subject=pump;
estimate 'alpha1-alpha2' alpha1-alpha2;
estimate 'beta1-beta2' beta1-beta2;
run;
