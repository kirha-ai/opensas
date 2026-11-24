/* STAT-NLMIXED-005: NLMIXED — REPLICATE / Modeling Assumptions and Notation / Integral Approximations
 * Source: S154 / Chapter 89 / `REPLICATE Statement` (PDF pp. 7125–7126); S154 / Chapter 89 / `Modeling Assumptions and Notation` (PDF pp. 7128–7129); S154 / Chapter 89 / `Integral Approximations` (PDF pp. 7129–7131).
 * Discriminates: Example 89.3: Probit-Normal Model with Ordinal Data; explicit statements: REPLICATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data inhaler;
input clarity group time freq @@;
gt = group*time;
sub = floor((_n_+1)/2);
datalines;
1 0 0 59 1 0 1 59 1 0 0 35 2 0 1 35 1 0 0 3 3 0 1 3 1 0 0 2
4 0 1 2 2 0 0 11 1 0 1 11 2 0 0 27 2 0 1 27 2 0 0 2 3 0 1 2
2 0 0 1 4 0 1 1 4 0 0 1 1 0 1 1 4 0 0 1 2 0 1 1 1 1 0 63
1 1 1 63 1 1 0 13 2 1 1 13 2 1 0 40 1 1 1 40 2 1 0 15 2 1 1 15
3 1 0 7 1 1 1 7 3 1 0 2 2 1 1 2 3 1 0 1 3 1 1 1 4 1 0 2
1 1 1 2 4 1 0 1 3 1 1 1
;
proc nlmixed data=inhaler corr ecorr;
parms b0=0 b1=0 b2=0 b3=0 sd=1 i1=1 i2=1;
bounds i1 > 0, i2 > 0;
eta = b0 + b1*group + b2*time + b3*gt + u;
if (clarity=1) then p = probnorm(-eta);
else if (clarity=2) then
p = probnorm(i1-eta) - probnorm(-eta);
else if (clarity=3) then
p = probnorm(i1+i2-eta) - probnorm(i1-eta);
else p = 1 - probnorm(i1+i2-eta);
if (p > 1e-8) then ll = log(p);
else ll = -1e20;
model clarity ~ general(ll);
random u ~ normal(0,sd*sd) subject=sub;
replicate freq;
estimate 'thresh2' i1;
estimate 'thresh3' i1 + i2;
estimate 'icc' sd*sd/(1+sd*sd);
run;
