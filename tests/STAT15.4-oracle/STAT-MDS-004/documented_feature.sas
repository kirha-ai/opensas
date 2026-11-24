/* STAT-MDS-004: MDS — OUT= Data Set / Normalization of the Estimates / Comparison with Earlier Procedures
 * Source: S154 / Chapter 81 / `OUT= Data Set` (PDF pp. 6397–6398); S154 / Chapter 81 / `Normalization of the Estimates` (PDF pp. 6400–6401); S154 / Chapter 81 / `Comparison with Earlier Procedures` (PDF p. 6401).
 * Discriminates: Getting Started: MDS Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Analysis of Flying Mileages between Ten U.S. Cities';
ods graphics on;
proc mds data=sashelp.mileages level=absolute;
id city;
run;
