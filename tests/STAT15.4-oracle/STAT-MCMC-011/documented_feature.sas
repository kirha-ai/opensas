/* STAT-MCMC-011: MCMC — Spatial Prior / Floating Point Errors and Overflows / Handling Error Messages
 * Source: S154 / Chapter 80 / `Spatial Prior` (PDF pp. 6230–6232); S154 / Chapter 80 / `Floating Point Errors and Overflows` (PDF pp. 6232–6235); S154 / Chapter 80 / `Handling Error Messages` (PDF pp. 6235–6237).
 * Discriminates: Example 80.12: Change Point Models
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Change Point Model';
data stagnant;
input y x @@;
ind = _n_;
datalines;
1.12 -1.39 1.12 -1.39 0.99 -1.08 1.03 -1.08
0.92 -0.94 0.90 -0.80 0.81 -0.63 0.83 -0.63
0.65 -0.25 0.67 -0.25 0.60 -0.12 0.59 -0.12
0.51 0.01 0.44 0.11 0.43 0.11 0.43 0.11
0.33 0.25 0.30 0.25 0.25 0.34 0.24 0.34
0.13 0.44 -0.01 0.59 -0.13 0.70 -0.14 0.70
-0.30 0.85 -0.33 0.85 -0.46 0.99 -0.43 0.99
-0.65 1.19
;
proc sgplot data=stagnant;
scatter x=x y=y;
run;
proc mcmc data=stagnant outpost=postout seed=24860 ntu=1000
nmc=1000 nbi=200;
ods select PostSumInt;
ods output PostSumInt=ds;
array beta[2];
parms alpha cp beta1 beta2;
parms s2;
prior cp ~ unif(-1.3, 1.1);
prior s2 ~ uniform(0, 5);
prior alpha beta: ~ normal(0, v = 1e6);
j = 1 + (x >= cp);
mu = alpha + beta[j] * (x - cp);
model y ~ normal(mu, var=s2);
run;
data _null_;
set ds;
call symputx(parameter, mean);
run;
data b;
missing A;
input x1 @@;
if x1 eq .A then x1 = &cp;
if _n_ <= 2 then y1 = &alpha + &beta1 * (x1 - &cp);
else y1 = &alpha + &beta2 * (x1 - &cp);
datalines;
-1.5 A 1.2
;
proc kde data=postout;
univar cp / out=m1 (drop=count);
run;
data m1;
set m1;
density = (density / 25) - 0.653;
run;
data all;
set stagnant b m1;
run;
proc sgplot data=all noautolegend;
scatter x=x y=y;
series x=x1 y=y1 / lineattrs = graphdata2;
series x=value y=density / lineattrs = graphdata1;
run;
