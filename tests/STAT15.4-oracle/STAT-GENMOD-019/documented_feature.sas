/* STAT-GENMOD-019: GENMOD — Displayed Output for Classical Analysis / Displayed Output for Bayesian Analysis / Displayed Output for Exact Analysis / ODS Table Names
 * Source: S154 / Chapter 51 / `Displayed Output for Classical Analysis` (PDF pp. 3616–3624); S154 / Chapter 51 / `Displayed Output for Bayesian Analysis` (PDF pp. 3624–3626); S154 / Chapter 51 / `Displayed Output for Exact Analysis` (PDF pp. 3626–3627); S154 / Chapter 51 / `ODS Table Names` (PDF pp. 3627–3631).
 * Discriminates: Example 51.11: Exact Poisson Regression
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods trace on;
data ingots;
input Heat Soak Notready Total @@;
lnTotal= log(Total);
datalines;
7 1.0 0 10 14 1.0 0 31 27 1.0 1 56 51 1.0 3 13
7 1.7 0 17 14 1.7 0 43 27 1.7 4 44 51 1.7 0 1
7 2.2 0 7 14 2.2 2 33 27 2.2 0 21 51 2.2 0 1
7 2.8 0 12 14 2.8 0 31 27 2.8 1 22 51 4.0 0 1
7 4.0 0 9 14 4.0 0 19 27 4.0 1 16
;
proc genmod data=ingots;
class Heat Soak / param=ref;
model Notready=Heat Soak / offset=lnTotal dist=Poisson link=log;
exact Heat Soak / joint estimate;
exactoptions statustime=10;
run;
ods trace off;
