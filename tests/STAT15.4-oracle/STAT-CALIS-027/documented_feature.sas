/* STAT-CALIS-027: CALIS — Latent Variable Scores
 * Source: S154 / Chapter 33 / `Latent Variable Scores` (PDF pp. 1793–1796).
 * Discriminates: Example 33.25: Fitting a Latent Growth Curve Model
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data growth;
input y1 y2 y3 y4 y5;
datalines;
17.6 21.4 25.6 32.1 37.7
13.2 14.3 18.9 20.3 25.4
11.6 13.5 17.4 22.1 39.6
10.7 11.1 13.2 18.2 21.4
18.7 23.7 28.6 31.5 34.0
18.3 19.2 20.5 23.2 25.9
9.2 13.5 17.8 19.2 21.1
18.3 23.5 27.9 30.2 34.6
11.2 15.6 20.8 22.7 30.4
17.0 22.9 26.9 31.9 35.6
10.4 13.6 18.0 25.6 29.3
17.7 19.0 22.5 28.5 30.7
14.5 19.4 21.1 28.8 31.5
20.0 21.4 28.9 30.2 35.6
14.6 19.3 21.7 28.5 32.0
11.7 15.2 19.1 23.7 28.7
;
proc calis method=ml data=growth nostand noparmname;
lineqs
y1 = 0. * Intercept + f_alpha + e1,
y2 = 0. * Intercept + f_alpha + 1 * f_beta + e2,
y3 = 0. * Intercept + f_alpha + 2 * f_beta + e3,
y4 = 0. * Intercept + f_alpha + 3 * f_beta + e4,
y5 = 0. * Intercept + f_alpha + 4 * f_beta + e5;
variance
f_alpha f_beta,
e1-e5 = 5 * evar;
mean
f_alpha f_beta;
cov
f_alpha f_beta;
fitindex on(only)=[chisq df probchi];
run;
proc calis method=ml data=growth nostand noparmname;
lineqs
y1 = 0. * Intercept + f_alpha + e1,
y2 = 0. * Intercept + f_alpha + 1 * f_beta + e2,
y3 = 0. * Intercept + f_alpha + 2 * f_beta + e3,
y4 = 0. * Intercept + f_alpha + 3 * f_beta + e4,
y5 = 0. * Intercept + f_alpha + 4 * f_beta + e5;
variance
f_alpha f_beta,
e1-e5;
mean
f_alpha f_beta;
cov
f_alpha f_beta;
fitindex on(only)=[chisq df probchi];
run;
