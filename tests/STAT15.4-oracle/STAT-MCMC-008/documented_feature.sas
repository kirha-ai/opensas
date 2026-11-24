/* STAT-MCMC-008: MCMC — Specifying a New Distribution / Truncation and Censoring / Some Useful SAS Functions
 * Source: S154 / Chapter 80 / `Specifying a New Distribution` (PDF pp. 6174–6175); S154 / Chapter 80 / `Truncation and Censoring` (PDF pp. 6178–6180); S154 / Chapter 80 / `Some Useful SAS Functions` (PDF pp. 6180–6182).
 * Discriminates: Example 80.17: Normal Regression with Interval Censoring
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Normal Regression with Interval Censoring';
data cosmetic;
t = .;
label tl = 'Time to Event (Months)';
input tl tr @@;
datalines;
45 . 6 10 . 7 46 . 46 . 7 16 17 . 7 14
37 44 . 8 4 11 15 . 11 15 22 . 46 . 46 .
25 37 46 . 26 40 46 . 27 34 36 44 46 . 36 48
37 . 40 . 17 25 46 . 11 18 38 . 5 12 37 .
. 5 18 . 24 . 36 . 5 11 19 35 17 25 24 .
32 . 33 . 19 26 37 . 34 . 36 .
;
proc mcmc data=cosmetic outpost=postout seed=1 nmc=1000 missing=AC nbi=200;
ods select PostSumInt;
parms mu 60 sigma 50;
prior mu ~ normal(0, sd=1000);
prior sigma ~ gamma(shape=0.001,iscale=0.001);
if (tl^=. and tr^=. and tl=tr) then
llike = logpdf('normal',tr,mu,sigma);
else if (tl^=. and tr=.) then
llike = logsdf('normal',tl,mu,sigma);
else if (tl=. and tr^=.) then
llike = logcdf('normal',tr,mu,sigma);
else
llike = log(sdf('normal',tl,mu,sigma) -
sdf('normal',tr,mu,sigma));
model general(llike);
run;
proc mcmc data=cosmetic outpost=postout seed=117207154
nmc=1000 missing=ACMODELY nbi=200;
ods select none;
parms mu 60 sigma 50;
prior mu ~ normal(0, sd=1000);
prior sigma ~ gamma(shape=0.001,iscale=0.001);
model t ~ normal(mu, sd=sigma, clower=tl, cupper=tr);
run;
