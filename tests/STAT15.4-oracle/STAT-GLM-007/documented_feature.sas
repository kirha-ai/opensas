/* STAT-GLM-007: GLM — Homogeneity of Variance in One-Way Models / Multivariate Analysis of Variance / Random-Effects Analysis
 * Source: S154 / Chapter 53 / `Homogeneity of Variance in One-Way Models` (PDF pp. 4143–4144); S154 / Chapter 53 / `Multivariate Analysis of Variance` (PDF pp. 4147–4149); S154 / Chapter 53 / `Random-Effects Analysis` (PDF pp. 4157–4160).
 * Discriminates: Example 53.8: Mixed Model Analysis of Variance with the RANDOM Statement
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data machine;
input machine person rating @@;
datalines;
1 1 52.0 1 2 51.8 1 2 52.8 1 3 60.0 1 4 51.1 1 4 52.3 1 5 50.9
1 5 51.8 1 5 51.4 1 6 46.4 1 6 44.8 1 6 49.2 2 1 64.0 2 2 59.7
2 2 60.0 2 2 59.0 2 3 68.6 2 3 65.8 2 4 63.2 2 4 62.8 2 4 62.2
2 5 64.8 2 5 65.0 2 6 43.7 2 6 44.2 2 6 43.0 3 1 67.5 3 1 67.2
3 1 66.9 3 2 61.5 3 2 61.7 3 2 62.3 3 3 70.8 3 3 70.6 3 3 71.0
3 4 64.1 3 4 66.2 3 4 64.0 3 5 72.1 3 5 72.0 3 5 71.1 3 6 62.0
3 6 61.4 3 6 60.5
;
proc glm data=machine;
class machine person;
model rating=machine person machine*person;
random person machine*person / test;
run;
proc mixed data=machine method=type3;
class machine person;
model rating = machine;
random person machine*person;
run;
