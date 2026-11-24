/* STAT-MCMC-019: MCMC — Regenerating Diagnostics Plots / Caterpillar Plot / ODS Graphics
 * Source: S154 / Chapter 80 / `Regenerating Diagnostics Plots` (PDF pp. 6208–6210); S154 / Chapter 80 / `Caterpillar Plot` (PDF pp. 6210–6212); S154 / Chapter 80 / `ODS Graphics` (PDF pp. 6244–6245).
 * Discriminates: Native chain diagnostics and an independently regenerated posterior trace from OUTPOST.
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

ods graphics on;
ods trace on;
proc mcmc data=sample outpost=posterior seed=314159 nmc=1500 nbi=300 plots=all;
 parms mu 80 sigma2 200;
 prior mu ~ normal(0,var=10000);
 prior sigma2 ~ igamma(shape=3,scale=300);
 model x ~ normal(mu,var=sigma2);
run;
proc sgplot data=posterior;
 series x=Iteration y=mu;
run;
proc print data=posterior(obs=8); run;
ods trace off;
ods graphics off;
