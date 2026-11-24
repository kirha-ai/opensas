/* STAT-POWER-017: POWER — PLOT / ODS Graphics
 * Source: S154 / Chapter 96 / `PLOT Statement` (PDF pp. 7808–7813); S154 / Chapter 96 / `ODS Graphics` (PDF pp. 7917–7918).
 * Discriminates: Getting Started: POWER Procedure; explicit statements: PLOT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;
proc power;
onesamplemeans
mean = 8
ntotal = 150
stddev = 40
power = .;
run;
ods graphics on;
proc power;
onesamplemeans
mean = 5 10
ntotal = 150
stddev = 30 50
power = .;
plot x=n min=100 max=200;
run;
ods graphics off;
proc power;
twosamplemeans
groupmeans = (13 14) (13 14.5) (13 15)
stddev = 1.2 1.7
groupweights = 1 | 1 2 3
power = 0.9
ntotal = .;
run;
proc power;
twosamplemeans
nfractional
meandiff = 1 to 2 by 0.5
stddev = 1.2 1.7
groupweights = (1 1) (1 2) (1 3)
power = 0.9
ntotal = .;
run;
ods trace off;
ods trace off;
ods graphics off;
