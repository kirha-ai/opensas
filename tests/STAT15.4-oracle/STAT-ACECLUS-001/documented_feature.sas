/* STAT-ACECLUS-001: ACECLUS — Data input, variable roles, and basic options
 * Source: S154 / Chapter 27 / `PROC ACECLUS Statement` (PDF pp. 1028–1033); S154 / Chapter 27 / `BY Statement` (PDF pp. 1033–1034); S154 / Chapter 27 / `FREQ Statement` (PDF p. 1034); S154 / Chapter 27 / `VAR Statement` (PDF p. 1034); S154 / Chapter 27 / `WEIGHT Statement` (PDF pp. 1034–1035); S154 / Chapter 27 / `Missing Values` (PDF p. 1035).
 * Discriminates: Verified default procedure context; explicit statements: FREQ, VAR
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Fisher (1936) Iris Data';
proc aceclus data=sashelp.iris out=ace p=.02 outstat=score;
var SepalLength SepalWidth PetalLength PetalWidth ;
run;
proc sgplot data=ace;
scatter y=can2 x=can1 / group=Species;
keylegend / title="Species";
run;
proc fastclus data=ace maxc=3 maxiter=10 conv=0 out=clus;
var can:;
run;
proc freq;
tables cluster*Species;
run;
