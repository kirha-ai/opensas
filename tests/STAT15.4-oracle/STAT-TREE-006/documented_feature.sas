/* STAT-TREE-006: TREE — Official examples and feature integration regression
 * Source: S154 / Chapter 127 / `Examples: TREE Procedure` (PDF pp. 10585–10594).
 * Discriminates: Example 127.2: Iris Data
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
ods graphics on;
proc cluster data=sashelp.iris method=twostage print=10
outtree=tree k=8 noeigen;
var SepalLength SepalWidth PetalLength PetalWidth;
copy Species;
run;
proc tree data=tree horizontal lineprinter pages=1 maxh=10;
id species;
run;
