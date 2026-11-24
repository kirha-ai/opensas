/* STAT-ACECLUS-006: ACECLUS — Computational Resources
 * Source: S154 / Chapter 27 / `Computational Resources` (PDF pp. 1036–1037).
 * Discriminates: Verified default procedure context
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
