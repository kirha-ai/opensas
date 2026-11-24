/* STAT-MCMC-022: MCMC — Official examples and feature integration regression
 * Source: S154 / Chapter 80 / `Examples: MCMC Procedure` (PDF pp. 6245–6373).
 * Discriminates: Example 80.7: Logistic Regression Random-Effects Model
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Logistic Regression Random-Effects Model';
data seeds;
input r n seed extract @@;
ind = _N_;
datalines;
10 39 0 0 23 62 0 0 23 81 0 0 26 51 0 0
17 39 0 0 5 6 0 1 53 74 0 1 55 72 0 1
32 51 0 1 46 79 0 1 10 13 0 1 8 16 1 0
10 30 1 0 8 28 1 0 23 45 1 0 0 4 1 0
3 12 1 1 22 41 1 1 15 30 1 1 32 51 1 1
3 7 1 1
;
proc mcmc data=seeds outpost=postout seed=332786 nmc=1000 nbi=200;
ods select PostSumInt;
parms beta0 0 beta1 0 beta2 0 beta3 0 s2 1;
prior s2 ~ igamma(0.01, s=0.01);
prior beta: ~ general(0);
w = beta0 + beta1*seed + beta2*extract + beta3*seed*extract;
random delta ~ normal(w, var=s2) subject=ind;
pi = logistic(delta);
model r ~ binomial(n = n, p = pi);
run;
