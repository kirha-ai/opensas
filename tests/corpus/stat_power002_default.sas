/* STAT-POWER-002: POWER — Forward and inverse test power and sample size calculations
 * Source: S154 / Chapter 96 / `Getting Started: POWER Procedure` (PDF pp. 7737–7744); S154 / Chapter 96 / `Overview: POWER Procedure` (PDF pp. 7735–7737).
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
