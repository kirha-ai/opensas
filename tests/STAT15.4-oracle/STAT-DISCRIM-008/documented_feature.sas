/* STAT-DISCRIM-008: DISCRIM — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 42 / `Displayed Output` (PDF pp. 2681–2685); S154 / Chapter 42 / `ODS Table Names` (PDF pp. 2685–2687).
 * Discriminates: Getting Started: DISCRIM Procedure
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
title 'Fish Measurement Data';
proc discrim data=sashelp.fish;
class Species;
run;
ods trace off;
