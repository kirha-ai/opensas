/* STAT-CANDISC-004: CANDISC — Output Data Sets
 * Source: S154 / Chapter 35 / `Output Data Sets` (PDF pp. 2163–2165).
 * Discriminates: Example 35.1: Analyzing Iris Data by Using PROC CANDISC
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
proc candisc data=sashelp.iris out=outcan distance anova;
class Species;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
