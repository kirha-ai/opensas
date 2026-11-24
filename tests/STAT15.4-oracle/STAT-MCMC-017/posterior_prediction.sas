/* STAT-MCMC-017: MCMC — PREDDIST
 * Source: S154 / Chapter 80 / `PREDDIST Statement` (PDF pp. 6133–6134).
 * Discriminates: Explicit PREDDIST and printed posterior predictive draws.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data sample;
 input x y group $ freq weight;
 datalines;
43 40 A 1 1
90 84 A 2 1
84 88 A 1 2
87 80 A 1 1
116 110 A 1 1
95 91 A 1 2
86 79 B 1 1
99 101 B 2 1
93 90 B 1 2
92 85 B 1 1
121 115 B 1 1
71 72 B 1 2
;
run;
proc mcmc data=sample seed=271828 nbi=100 nmc=1000 diag=none; parms mu 90; prior mu ~ normal(0,var=10000); model x ~ normal(mu,var=100); preddist outpred=posterior_prediction nsim=100;
run;

proc print data=posterior_prediction(obs=5); run;
