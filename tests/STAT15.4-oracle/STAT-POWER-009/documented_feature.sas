/* STAT-POWER-009: POWER — Grouped-Number-Lists / Name-Lists / Grouped-Name-Lists
 * Source: S154 / Chapter 96 / `Grouped-Number-Lists` (PDF pp. 7850–7852); S154 / Chapter 96 / `Name-Lists` (PDF p. 7852); S154 / Chapter 96 / `Grouped-Name-Lists` (PDF pp. 7852–7853).
 * Discriminates: Getting Started: POWER Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

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
